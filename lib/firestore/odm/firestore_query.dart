import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'firestore_converter.dart';
import 'firestore_field.dart';
import 'firestore_sdk_interface.dart';
import 'firestore_types.dart';

class FirestoreQueryState {
  final IList<WhereClause> where;
  final IList<OrderBy> orderBy;
  final int? limit;
  final DocumentSnapshot<Map<String, dynamic>>? startAfter;
  final DocumentSnapshot<Map<String, dynamic>>? endBefore;

  const FirestoreQueryState({
    this.where = const IList.empty(),
    this.orderBy = const IList.empty(),
    this.limit,
    this.startAfter,
    this.endBefore,
  });

  FirestoreQueryState copyWith({
    IList<WhereClause>? where,
    IList<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  }) {
    return FirestoreQueryState(
      where: where ?? this.where,
      orderBy: orderBy ?? this.orderBy,
      limit: limit ?? this.limit,
      startAfter: startAfter ?? this.startAfter,
      endBefore: endBefore ?? this.endBefore,
    );
  }
}

abstract class FirestoreQuery<T> {
  final FirestoreSDK sdk;

  // abstract properties
  final String path;
  FirestoreConverter<T> get converter;
  FirestoreDocumentFields<T> get fields;

  final FirestoreQueryState state;

  const FirestoreQuery(this.sdk, this.path)
      : state = const FirestoreQueryState();

  const FirestoreQuery.withState(this.sdk, this.path, this.state);

  FirestoreQuery<T> where(
      FieldQuery Function(FirestoreDocumentFields<T> fields) fieldSelector) {
    final fieldQuery = fieldSelector(fields);
    return getQuery(state.copyWith(
      where: state.where.addAll(fieldQuery.clauses),
    ));
  }

  FirestoreQuery<T> orderBy(
      FirestoreField Function(FirestoreDocumentFields<T> fields) fieldSelector,
      {OrderDirection direction = OrderDirection.asc}) {
    final field = fieldSelector(fields);
    return getQuery(state.copyWith(
      orderBy: state.orderBy.add(OrderBy(
        field: field.path,
        direction: direction,
      )),
    ));
  }

  FirestoreQuery<T> limit(int limit) {
    return getQuery(state.copyWith(limit: limit));
  }

  FirestoreQuery<T> startAfter(DocumentSnapshot<T> document) {
    return getQuery(
        state.copyWith(startAfter: document.mapData(converter.toJson)));
  }

  FirestoreQuery<T> endBefore(DocumentSnapshot<T> document) {
    return getQuery(
        state.copyWith(endBefore: document.mapData(converter.toJson)));
  }

  Future<List<DocumentSnapshot<T>>> get() async {
    final snapshots = await sdk.getCollection(
      path,
      where: state.where.unlock,
      orderBy: state.orderBy.unlock,
      limit: state.limit,
      startAfter: state.startAfter,
      endBefore: state.endBefore,
    );

    return snapshots
        .map((snapshot) => snapshot.mapData(converter.fromJson))
        .toList();
  }

  Stream<QuerySnapshot<T>> snapshots() {
    return sdk
        .queryStream(
          path,
          where: state.where.unlock,
          orderBy: state.orderBy.unlock,
          limit: state.limit,
          startAfter: state.startAfter,
          endBefore: state.endBefore,
        )
        .map(
          (snapshots) => QuerySnapshot(
            docs: snapshots
                .map((snapshot) => snapshot.mapData(converter.fromJson))
                .toList(),
          ),
        );
  }

  Future<int> count() async {
    return sdk.collectionCount(
      path,
      where: state.where.unlock,
    );
  }

  FirestoreQuery<T> getQuery(FirestoreQueryState state);
}

mixin FieldQueryMixin<T, Query extends FirestoreQuery<T>,
    Fields extends FirestoreDocumentFields<T>> on FirestoreQuery<T> {
  @override
  Query where(FieldQuery Function(Fields fields) fieldSelector) =>
      super.where((fields) => fieldSelector(fields as Fields)) as Query;

  @override
  Query orderBy(FirestoreField Function(Fields fields) fieldSelector,
          {OrderDirection direction = OrderDirection.asc}) =>
      super.orderBy((fields) => fieldSelector(fields as Fields),
          direction: direction) as Query;

  @override
  Query limit(int limit) => super.limit(limit) as Query;

  @override
  Query startAfter(DocumentSnapshot<T> document) =>
      super.startAfter(document) as Query;

  @override
  Query endBefore(DocumentSnapshot<T> document) =>
      super.endBefore(document) as Query;
}
