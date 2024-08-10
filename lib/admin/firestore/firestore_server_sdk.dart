import 'dart:async';
import 'dart:developer';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis/firestore/v1.dart' as firestore;

import '../../firestore/odm/firestore_sdk_interface.dart';
import '../../firestore/odm/firestore_types.dart';
import '../firebase_admin.dart';

class FirestorePath {
  final String basePath;
  final List<String> segments;
  final bool isCollection;

  const FirestorePath(this.basePath, this.segments, this.isCollection);

  String get id => segments.last;

  String get parentPath => segments.length > 1
      ? '$basePath/${segments.sublist(0, segments.length - 1).join('/')}'
      : basePath;

  String get fullPath => '$basePath/${segments.join('/')}';

  String get collectionPath => isCollection ? fullPath : parentPath;

  String get documentPath => isCollection
      ? throw StateError('This path represents a collection')
      : fullPath;
}

class FirestoreServerSDK implements FirestoreSDK {
  final FirebaseAdminApp _app;
  final String _databaseId;
  FirestoreApi get _api => FirestoreApi(_app.client);

  String get _projectPath => 'projects/${_app.projectId}';

  String get _databasePath => '$_projectPath/databases/$_databaseId';

  FirestorePath _analyzePath(String path) {
    final segments =
        path.trim().split('/').where((part) => part.isNotEmpty).toList();

    if (segments.isEmpty) {
      throw ArgumentError('Invalid Firestore path: $path');
    }

    final basePath = '$_databasePath/documents';
    final isCollection = segments.length % 2 !=
        0; // Odd number of segments indicates a collection

    return FirestorePath(basePath, segments, isCollection);
  }

  FirestoreServerSDK(this._app, {String databaseId = '(default)'})
      : _databaseId = databaseId;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
      String path) async {
    final pathInfo = _analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    try {
      final document =
          await _api.projects.databases.documents.get(pathInfo.documentPath);
      return DocumentSnapshot<Map<String, dynamic>>(
        id: pathInfo.id,
        data: _convertFromFirestoreDocument(document),
        exists: true,
      );
    } catch (e) {
      if (e is firestore.DetailedApiRequestError && e.status == 404) {
        return DocumentSnapshot<Map<String, dynamic>>(
          id: pathInfo.id,
          data: null,
          exists: false,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> setDocument(String path, Map<String, dynamic> data,
      {bool merge = false}) async {
    final pathInfo = _analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    final writes = _createWritesForDocument(pathInfo.documentPath, data, merge);

    await _api.projects.databases.documents.commit(
      firestore.CommitRequest()..writes = writes,
      _databasePath,
    );
  }

  @override
  Future<void> updateDocument(String path, Map<String, dynamic> data) async {
    final pathInfo = _analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    final writes = _createWritesForDocument(pathInfo.documentPath, data, true);

    await _api.projects.databases.documents.commit(
      firestore.CommitRequest()..writes = writes,
      _databasePath,
    );
  }

  List<firestore.Write> _createWritesForDocument(
      String docPath, Map<String, dynamic> data, bool merge) {
    final writes = <firestore.Write>[];
    final updateMask = firestore.DocumentMask();
    final updateTransforms = <firestore.FieldTransform>[];
    final filteredData = Map<String, dynamic>.from(data);

    data.forEach((key, value) {
      if (value is FieldValue) {
        filteredData.remove(key);
        switch (value) {
          case DeleteFieldValue():
            if (merge) {
              // For merge operations (including updates), we include the field in the update mask
              updateMask.fieldPaths ??= [];
              updateMask.fieldPaths!.add(key);
            }
            // For set operations without merge, we don't need to do anything special
            // The field will be absent from filteredData, effectively deleting it
            break;
          case ServerTimestampFieldValue():
            updateTransforms.add(firestore.FieldTransform()
              ..fieldPath = key
              ..setToServerValue = 'REQUEST_TIME');
            break;
          case IncrementFieldValue():
            updateTransforms.add(firestore.FieldTransform()
              ..fieldPath = key
              ..increment = _valueToFirestoreValue(value.value));
            break;
          case ArrayUnionFieldValue():
            updateTransforms.add(firestore.FieldTransform()
              ..fieldPath = key
              ..appendMissingElements = firestore.ArrayValue(
                  values: value.elements.map(_valueToFirestoreValue).toList()));
            break;
          case ArrayRemoveFieldValue():
            updateTransforms.add(firestore.FieldTransform()
              ..fieldPath = key
              ..removeAllFromArray = firestore.ArrayValue(
                  values: value.elements.map(_valueToFirestoreValue).toList()));
            break;
        }
      } else {
        updateMask.fieldPaths ??= [];
        updateMask.fieldPaths!.add(key);
      }
    });

    final document = _mapToFirestoreDocument(docPath, filteredData);
    final write = firestore.Write()
      ..update = document
      ..updateTransforms = updateTransforms;

    if (merge) {
      write.updateMask = updateMask;
    }

    writes.add(write);
    return writes;
  }

  @override
  Future<void> deleteDocument(String path) async {
    final pathInfo = _analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    await _api.projects.databases.documents.delete(pathInfo.documentPath);
  }

  @override
  Future<DocumentReference> addDocument(
      String collectionPath, Map<String, dynamic> data) async {
    final pathInfo = _analyzePath(collectionPath);

    if (!pathInfo.isCollection) {
      throw ArgumentError(
          'The provided path must point to a collection: $collectionPath');
    }

    final writes = _createWritesForDocument(pathInfo.fullPath, data, false);

    try {
      final response = await _api.projects.databases.documents.commit(
        firestore.CommitRequest()..writes = writes,
        _databasePath,
      );

      // The last write operation should be the newly added document
      final newDocPath = response.writeResults?.last.updateTime?.toString() ??
          (throw Exception('Failed to get the path of the new document'));

      final newDocId = newDocPath.split('/').last;
      final newDocFullPath = '${pathInfo.fullPath}/$newDocId';

      return DocumentReference(
        id: newDocId,
        path: newDocFullPath.split('${pathInfo.basePath}/')[1],
      );
    } catch (e) {
      throw Exception('Error in addDocument: $e');
    }
  }

  @override
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> getCollection(
    String path, {
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  }) async {
    final pathInfo = _analyzePath(path);

    if (!pathInfo.isCollection) {
      throw ArgumentError(
          'The provided path must point to a collection: $path');
    }

    final structuredQuery = firestore.StructuredQuery()
      ..from = [firestore.CollectionSelector()..collectionId = pathInfo.id]
      ..where = _buildCompositeFilter(where)
      ..orderBy = orderBy?.map(_buildOrderBy).toList()
      ..limit = limit
      ..startAt = startAfter != null ? _buildCursor(startAfter) : null
      ..endAt = endBefore != null ? _buildCursor(endBefore) : null;

    final request = firestore.RunQueryRequest()
      ..structuredQuery = structuredQuery;
    final response = await _api.projects.databases.documents
        .runQuery(request, pathInfo.parentPath);

    return response
        .where((doc) => doc.document != null)
        .map((doc) => DocumentSnapshot<Map<String, dynamic>>(
              id: doc.document!.name!.split('/').last,
              data: _convertFromFirestoreDocument(doc.document!),
              exists: true,
            ))
        .toList();
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> documentStream(String path) {
    throw UnimplementedError(
        'Real-time document streams are not supported in server-side Firestore');
  }

  @override
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> queryStream(
    String path, {
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  }) {
    throw UnimplementedError(
        'Real-time query streams are not supported in server-side Firestore');
  }

  @override
  Future<T> runTransaction<T>(
      FutureOr<T> Function(Transaction) updateFunction) async {
    final beginResponse = await _api.projects.databases.documents
        .beginTransaction(
            firestore.BeginTransactionRequest()
              ..options = (firestore.TransactionOptions()
                ..readWrite = firestore.ReadWrite()),
            _databasePath);
    final transactionId = beginResponse.transaction!;

    final transaction = _ServerFirestoreTransaction(this, transactionId);

    try {
      final result = await updateFunction(transaction);
      await _api.projects.databases.documents.commit(
          firestore.CommitRequest()
            ..transaction = transactionId
            ..writes = transaction.writes,
          _databasePath);
      return result;
    } catch (e) {
      await _api.projects.databases.documents.rollback(
          firestore.RollbackRequest()..transaction = transactionId,
          _databasePath);
      rethrow;
    }
  }

  @override
  Future<int> collectionCount(
    String path, {
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  }) async {
    final pathInfo = _analyzePath(path);

    if (!pathInfo.isCollection) {
      throw ArgumentError(
          'The provided path must point to a collection: $path');
    }

    final structuredQuery = firestore.StructuredQuery()
      ..from = [firestore.CollectionSelector()..collectionId = pathInfo.id]
      ..where = _buildCompositeFilter(where)
      ..orderBy = orderBy?.map(_buildOrderBy).toList()
      ..limit = limit
      ..startAt = startAfter != null ? _buildCursor(startAfter) : null
      ..endAt = endBefore != null ? _buildCursor(endBefore) : null
      ..select = (firestore.Projection()..fields = []);

    final aggregation = firestore.Aggregation()..count = firestore.Count();

    final request = firestore.RunAggregationQueryRequest()
      ..structuredAggregationQuery = (firestore.StructuredAggregationQuery()
        ..structuredQuery = structuredQuery
        ..aggregations = [aggregation]);

    final response = await _api.projects.databases.documents
        .runAggregationQuery(request, pathInfo.parentPath);

    final countValue = response.first.result!.aggregateFields!['count']!;
    if (countValue.integerValue != null) {
      return int.parse(countValue.integerValue!);
    } else {
      throw FormatException('Unexpected count format: $countValue');
    }
  }

  @override
  Stream<int> collectionCountStream(String path, {List<WhereClause>? where}) {
    throw UnimplementedError(
        'Real-time collection count streams are not supported in server-side Firestore');
  }

  @override
  String generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  // Helper methods

  firestore.Document _mapToFirestoreDocument(
      String path, Map<String, dynamic> data) {
    return firestore.Document()
      ..name = path
      ..fields = data
          .map((key, value) => MapEntry(key, _valueToFirestoreValue(value)));
  }

  Map<String, dynamic> _convertFromFirestoreDocument(
      firestore.Document document) {
    return document.fields!
        .map((key, value) => MapEntry(key, _convertFromFirestoreValue(value)));
  }

  firestore.Value _valueToFirestoreValue(dynamic value) {
    if (value == null) {
      return firestore.Value(nullValue: 'NULL_VALUE');
    } else if (value is bool) {
      return firestore.Value(booleanValue: value);
    } else if (value is int) {
      return firestore.Value(integerValue: value.toString());
    } else if (value is double) {
      return firestore.Value(doubleValue: value);
    } else if (value is String) {
      return firestore.Value(stringValue: value);
    } else if (value is List) {
      return firestore.Value(
        arrayValue: (firestore.ArrayValue(
          values: value.map(_valueToFirestoreValue).toList(),
        )),
      );
    } else if (value is Map) {
      return firestore.Value(
        mapValue: (firestore.MapValue(
          fields: value.map(
            (k, v) => MapEntry(
              k,
              _valueToFirestoreValue(v),
            ),
          ),
        )),
      );
    } else {
      throw ArgumentError('Unsupported type: ${value.runtimeType}');
    }
  }

  dynamic _convertFromFirestoreValue(firestore.Value value) {
    if (value.nullValue != null) return null;
    if (value.booleanValue != null) return value.booleanValue;
    if (value.integerValue != null) return int.parse(value.integerValue!);
    if (value.doubleValue != null) return value.doubleValue;
    if (value.stringValue != null) return value.stringValue;
    if (value.arrayValue != null) {
      return value.arrayValue!.values!.map(_convertFromFirestoreValue).toList();
    }
    if (value.mapValue != null) {
      return value.mapValue!.fields!.map(
          (key, value) => MapEntry(key, _convertFromFirestoreValue(value)));
    }
    throw ArgumentError('Unsupported Firestore value type');
  }

  firestore.Filter? _buildCompositeFilter(List<WhereClause>? whereClauses) {
    if (whereClauses == null || whereClauses.isEmpty) return null;

    final filters = whereClauses.map((clause) {
      return firestore.Filter()
        ..fieldFilter = (firestore.FieldFilter()
          ..field = (firestore.FieldReference()..fieldPath = clause.field)
          ..op = _mapOperator(clause.operator)
          ..value = _valueToFirestoreValue(clause.value));
    }).toList();

    return firestore.Filter()
      ..compositeFilter = (firestore.CompositeFilter()
        ..op = 'AND'
        ..filters = filters);
  }

  firestore.Order _buildOrderBy(OrderBy order) {
    return firestore.Order()
      ..field = (firestore.FieldReference()..fieldPath = order.field)
      ..direction =
          order.direction == OrderDirection.desc ? 'DESCENDING' : 'ASCENDING';
  }

  firestore.Cursor _buildCursor(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return firestore.Cursor()
      ..values = snapshot.data!.values.map(_valueToFirestoreValue).toList();
  }

  String _mapOperator(WhereOperator op) {
    switch (op) {
      case WhereOperator.equalTo:
        return 'EQUAL';
      case WhereOperator.notEqualTo:
        return 'NOT_EQUAL';
      case WhereOperator.lessThan:
        return 'LESS_THAN';
      case WhereOperator.lessThanOrEqualTo:
        return 'LESS_THAN_OR_EQUAL';
      case WhereOperator.greaterThan:
        return 'GREATER_THAN';
      case WhereOperator.greaterThanOrEqualTo:
        return 'GREATER_THAN_OR_EQUAL';
      case WhereOperator.arrayContains:
        return 'ARRAY_CONTAINS';
      case WhereOperator.arrayContainsAny:
        return 'ARRAY_CONTAINS_ANY';
      case WhereOperator.whereIn:
        return 'IN';
      case WhereOperator.whereNotIn:
        return 'NOT_IN';
      case WhereOperator.isNull:
        return 'IS_NULL';
    }
  }
}

class _ServerFirestoreTransaction implements Transaction {
  final FirestoreServerSDK _sdk;
  final String _transactionId;
  final List<firestore.Write> writes = [];

  _ServerFirestoreTransaction(this._sdk, this._transactionId);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
      String path) async {
    final pathInfo = _sdk._analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    final document = await _sdk._api.projects.databases.documents
        .get(pathInfo.documentPath, transaction: _transactionId);
    return DocumentSnapshot<Map<String, dynamic>>(
      id: pathInfo.id,
      data: _sdk._convertFromFirestoreDocument(document),
      exists: true,
    );
  }

  @override
  void setDocument(String path, Map<String, dynamic> data,
      {bool merge = false}) {
    final pathInfo = _sdk._analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    writes.addAll(
        _sdk._createWritesForDocument(pathInfo.documentPath, data, merge));
  }

  @override
  void updateDocument(String path, Map<String, dynamic> data) {
    final pathInfo = _sdk._analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    writes.addAll(
        _sdk._createWritesForDocument(pathInfo.documentPath, data, true));
  }

  @override
  void deleteDocument(String path) {
    final pathInfo = _sdk._analyzePath(path);

    if (pathInfo.isCollection) {
      throw ArgumentError('The provided path must point to a document: $path');
    }

    writes.add(firestore.Write()..delete = pathInfo.documentPath);
  }
}
