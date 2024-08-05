import 'firestore_types.dart';

abstract class Cardinality {}

class Nullable extends Cardinality {}

class NonNullable extends Cardinality {}

class FirestoreField<T, C extends Cardinality> {
  final String path;
  const FirestoreField(this.path);
}

abstract class FieldQuery<T, C extends Cardinality> {
  List<WhereClause> get clauses;
  FieldQuery<T, C> isEqualTo(T value);
  FieldQuery<T, C> isNotEqualTo(T value);
  FieldQuery<T, C> whereIn(List<T> values);
  FieldQuery<T, C> whereNotIn(List<T> values);
}

class _FieldQueryImpl<T, C extends Cardinality> implements FieldQuery<T, C> {
  @override
  final List<WhereClause> clauses;
  final String path;

  _FieldQueryImpl(this.path, [this.clauses = const []]);

  @override
  FieldQuery<T, C> isEqualTo(T value) =>
      _addClause(WhereOperator.equalTo, value);

  @override
  FieldQuery<T, C> isNotEqualTo(T value) =>
      _addClause(WhereOperator.notEqualTo, value);

  @override
  FieldQuery<T, C> whereIn(List<T> values) =>
      _addClause(WhereOperator.whereIn, values);

  @override
  FieldQuery<T, C> whereNotIn(List<T> values) =>
      _addClause(WhereOperator.whereNotIn, values);

  FieldQuery<T, C> _addClause(WhereOperator operator, dynamic value) {
    return _FieldQueryImpl<T, C>(path, [
      ...clauses,
      WhereClause(field: path, operator: operator, value: value)
    ]);
  }
}

extension FieldQueryExtension<T, C extends Cardinality>
    on FirestoreField<T, C> {
  FieldQuery<T, C> get query => _FieldQueryImpl<T, C>(path);
}

extension StringFieldQueryExtension<C extends Cardinality>
    on FirestoreField<String, C> {
  FieldQuery<String, C> startsWith(String prefix) {
    final endPrefix = prefix.substring(0, prefix.length - 1) +
        String.fromCharCode(prefix.codeUnitAt(prefix.length - 1) + 1);
    return _FieldQueryImpl<String, C>(path, [
      WhereClause(
          field: path,
          operator: WhereOperator.greaterThanOrEqualTo,
          value: prefix),
      WhereClause(
          field: path, operator: WhereOperator.lessThan, value: endPrefix)
    ]);
  }
}

extension NumericFieldQueryExtension<C extends Cardinality>
    on FirestoreField<num, C> {
  FieldQuery<num, C> isLessThan(num value) => _FieldQueryImpl<num, C>(path, [
        WhereClause(field: path, operator: WhereOperator.lessThan, value: value)
      ]);
  FieldQuery<num, C> isLessThanOrEqualTo(num value) =>
      _FieldQueryImpl<num, C>(path, [
        WhereClause(
            field: path,
            operator: WhereOperator.lessThanOrEqualTo,
            value: value)
      ]);
  FieldQuery<num, C> isGreaterThan(num value) => _FieldQueryImpl<num, C>(path, [
        WhereClause(
            field: path, operator: WhereOperator.greaterThan, value: value)
      ]);
  FieldQuery<num, C> isGreaterThanOrEqualTo(num value) =>
      _FieldQueryImpl<num, C>(path, [
        WhereClause(
            field: path,
            operator: WhereOperator.greaterThanOrEqualTo,
            value: value)
      ]);

  FieldQuery<num, C> between(num lower, num upper) =>
      _FieldQueryImpl<num, C>(path, [
        WhereClause(
            field: path,
            operator: WhereOperator.greaterThanOrEqualTo,
            value: lower),
        WhereClause(
            field: path,
            operator: WhereOperator.lessThanOrEqualTo,
            value: upper)
      ]);
}

extension ListFieldQueryExtension<E, C extends Cardinality>
    on FirestoreField<List<E>, C> {
  FieldQuery<List<E>, C> arrayContains(E value) =>
      _FieldQueryImpl<List<E>, C>(path, [
        WhereClause(
            field: path, operator: WhereOperator.arrayContains, value: value)
      ]);
  FieldQuery<List<E>, C> arrayContainsAny(List<E> values) =>
      _FieldQueryImpl<List<E>, C>(path, [
        WhereClause(
            field: path,
            operator: WhereOperator.arrayContainsAny,
            value: values)
      ]);
}

abstract class FirestoreDocumentFields<T> {
  final String path;
  const FirestoreDocumentFields([this.path = '']);
}
