import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;

import 'odm/firestore_sdk_interface.dart';
import 'odm/firestore_types.dart';

class ClientFirestoreSDK implements FirestoreSDK {
  final cf.FirebaseFirestore _firestore;

  ClientFirestoreSDK(this._firestore);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
      String path) async {
    final docSnapshot = await _firestore.doc(path).get();
    return DocumentSnapshot<Map<String, dynamic>>(
      id: docSnapshot.id,
      data: docSnapshot.data(),
      exists: docSnapshot.exists,
    );
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
    cf.Query query = _firestore.collection(path);

    query = _applyQueryConstraints(
        query, where, orderBy, limit, startAfter, endBefore);

    final querySnapshot = await query.get();
    return querySnapshot.docs
        .map((doc) => DocumentSnapshot<Map<String, dynamic>>(
              id: doc.id,
              data: doc.data() as Map<String, dynamic>?,
              exists: true,
            ))
        .toList();
  }

  @override
  Future<void> setDocument(String path, Map<String, dynamic> data,
      {bool merge = false}) async {
    final convertedData = _convertFieldValues(data);
    await _firestore.doc(path).set(convertedData, cf.SetOptions(merge: merge));
  }

  @override
  Future<void> updateDocument(String path, Map<String, dynamic> data) async {
    final convertedData = _convertFieldValues(data);
    await _firestore.doc(path).update(convertedData);
  }

  @override
  Future<void> deleteDocument(String path) async {
    await _firestore.doc(path).delete();
  }

  @override
  Future<DocumentReference> addDocument(
      String collectionPath, Map<String, dynamic> data) async {
    final docRef = await _firestore.collection(collectionPath).add(data);
    return DocumentReference(id: docRef.id, path: docRef.path);
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> documentStream(String path) {
    return _firestore
        .doc(path)
        .snapshots()
        .map((docSnapshot) => DocumentSnapshot<Map<String, dynamic>>(
              id: docSnapshot.id,
              data: docSnapshot.data(),
              exists: docSnapshot.exists,
            ));
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
    cf.Query query = _firestore.collection(path);

    query = _applyQueryConstraints(
        query, where, orderBy, limit, startAfter, endBefore);

    return query.snapshots().map((querySnapshot) => querySnapshot.docs
        .map((doc) => DocumentSnapshot<Map<String, dynamic>>(
              id: doc.id,
              data: doc.data() as Map<String, dynamic>?,
              exists: true,
            ))
        .toList());
  }

  @override
  Future<T> runTransaction<T>(
      FutureOr<T> Function(Transaction) updateFunction) async {
    return _firestore.runTransaction((cf.Transaction cfTransaction) async {
      final transaction = _ClientFirestoreTransaction(cfTransaction, this);
      return await updateFunction(transaction);
    });
  }

  @override
  Future<int> collectionCount(String path,
      {List<WhereClause>? where,
      List<OrderBy>? orderBy,
      int? limit,
      DocumentSnapshot<Map<String, dynamic>>? startAfter,
      DocumentSnapshot<Map<String, dynamic>>? endBefore}) async {
    cf.Query query = _firestore.collection(path);

    query = _applyQueryConstraints(
        query, where, orderBy, limit, startAfter, endBefore);

    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  @override
  Stream<int> collectionCountStream(String path, {List<WhereClause>? where}) {
    cf.Query query = _firestore.collection(path);

    if (where != null) {
      for (final clause in where) {
        query = _applyWhereClause(query, clause);
      }
    }

    return query.snapshots().map((snapshot) => snapshot.docs.length);
  }

  @override
  String generateId() {
    return _firestore.collection('_').doc().id;
  }

  Map<String, dynamic> _convertFieldValues(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is FieldValue) {
        return MapEntry(key, _convertFieldValue(value));
      }
      return MapEntry(key, value);
    });
  }

  cf.FieldValue _convertFieldValue(FieldValue value) {
    return switch (value) {
      DeleteFieldValue() => cf.FieldValue.delete(),
      ServerTimestampFieldValue() => cf.FieldValue.serverTimestamp(),
      IncrementFieldValue(value: var incrementValue) =>
        cf.FieldValue.increment(incrementValue),
      ArrayUnionFieldValue(elements: var elements) =>
        cf.FieldValue.arrayUnion(elements),
      ArrayRemoveFieldValue(elements: var elements) =>
        cf.FieldValue.arrayRemove(elements),
    };
  }

  cf.Query _applyQueryConstraints(
    cf.Query query,
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  ) {
    if (where != null) {
      for (final clause in where) {
        query = _applyWhereClause(query, clause);
      }
    }

    if (orderBy != null) {
      for (final order in orderBy) {
        query = query.orderBy(order.field,
            descending: order.direction == OrderDirection.desc);
      }
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    if (startAfter != null) {
      final values = startAfter.data?.values.toList() ?? [];
      query = query.startAfter(values);
    }

    if (endBefore != null) {
      final values = endBefore.data?.values.toList() ?? [];
      query = query.endBefore(values);
    }

    return query;
  }

  cf.Query _applyWhereClause(cf.Query query, WhereClause clause) {
    switch (clause.operator) {
      case WhereOperator.equalTo:
        return query.where(clause.field, isEqualTo: clause.value);
      case WhereOperator.notEqualTo:
        return query.where(clause.field, isNotEqualTo: clause.value);
      case WhereOperator.lessThan:
        return query.where(clause.field, isLessThan: clause.value);
      case WhereOperator.lessThanOrEqualTo:
        return query.where(clause.field, isLessThanOrEqualTo: clause.value);
      case WhereOperator.greaterThan:
        return query.where(clause.field, isGreaterThan: clause.value);
      case WhereOperator.greaterThanOrEqualTo:
        return query.where(clause.field, isGreaterThanOrEqualTo: clause.value);
      case WhereOperator.arrayContains:
        return query.where(clause.field, arrayContains: clause.value);
      case WhereOperator.arrayContainsAny:
        return query.where(clause.field, arrayContainsAny: clause.value);
      case WhereOperator.whereIn:
        return query.where(clause.field, whereIn: clause.value);
      case WhereOperator.whereNotIn:
        return query.where(clause.field, whereNotIn: clause.value);
      case WhereOperator.isNull:
        return query.where(clause.field, isNull: true);
    }
  }
}

class _ClientFirestoreTransaction implements Transaction {
  final cf.Transaction _transaction;
  final ClientFirestoreSDK _sdk;

  _ClientFirestoreTransaction(this._transaction, this._sdk);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
      String path) async {
    final docSnapshot = await _transaction.get(_sdk._firestore.doc(path));
    return DocumentSnapshot<Map<String, dynamic>>(
      id: docSnapshot.id,
      data: docSnapshot.data(),
      exists: docSnapshot.exists,
    );
  }

  @override
  void setDocument(String path, Map<String, dynamic> data,
      {bool merge = false}) {
    final convertedData = _sdk._convertFieldValues(data);
    _transaction.set(
        _sdk._firestore.doc(path), convertedData, cf.SetOptions(merge: merge));
  }

  @override
  void updateDocument(String path, Map<String, dynamic> data) {
    final convertedData = _sdk._convertFieldValues(data);
    _transaction.update(_sdk._firestore.doc(path), convertedData);
  }

  @override
  void deleteDocument(String path) {
    _transaction.delete(_sdk._firestore.doc(path));
  }
}
