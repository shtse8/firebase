class DocumentSnapshot<T> {
  final String id;
  final T? data;
  final bool exists;

  T get requireData {
    if (data == null) {
      throw Exception('Document does not exist');
    }
    return data!;
  }

  const DocumentSnapshot({required this.id, this.data, required this.exists});

  DocumentSnapshot<E> mapData<E>(E Function(T data) mapper) {
    return DocumentSnapshot<E>(
      id: id,
      data: data != null ? mapper(data as T) : null,
      exists: exists,
    );
  }
}

class QuerySnapshot<T> {
  final List<DocumentSnapshot<T>> docs;

  const QuerySnapshot({required this.docs});

  QuerySnapshot<E> mapData<E>(E Function(T data) mapper) {
    return QuerySnapshot<E>(
      docs: docs.map((doc) => doc.mapData(mapper)).toList(),
    );
  }
}

class DocumentReference {
  final String id;
  final String path;

  DocumentReference({required this.id, required this.path});
}

class FieldValue {
  final String _operation;
  final dynamic _value;

  FieldValue._(this._operation, this._value);

  static FieldValue delete() => FieldValue._('delete', null);
  static FieldValue increment(num value) => FieldValue._('increment', value);
  static FieldValue arrayUnion(List<dynamic> elements) =>
      FieldValue._('arrayUnion', elements);
  static FieldValue arrayRemove(List<dynamic> elements) =>
      FieldValue._('arrayRemove', elements);

  Map<String, dynamic> toJson() => {
        '__type': 'FieldValue',
        'operation': _operation,
        'value': _value,
      };
}

enum WhereOperator {
  equalTo,
  notEqualTo,
  lessThan,
  lessThanOrEqualTo,
  greaterThan,
  greaterThanOrEqualTo,
  arrayContains,
  arrayContainsAny,
  whereIn,
  whereNotIn,
  isNull,
}

enum OrderDirection { asc, desc }

class WhereClause {
  final String field;
  final WhereOperator operator;
  final dynamic value;
  WhereClause(
      {required this.field, required this.operator, required this.value});
}

class OrderBy {
  final String field;
  final OrderDirection direction;
  OrderBy({required this.field, required this.direction});
}
