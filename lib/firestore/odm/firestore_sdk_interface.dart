import 'dart:async';

import 'package:uuid/uuid.dart';

import 'firestore_types.dart';

abstract class FirestoreSDK {
  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(String path);
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> getCollection(
    String path, {
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  });
  Future<void> setDocument(String path, Map<String, dynamic> data,
      {bool merge = false});
  Future<void> updateDocument(String path, Map<String, dynamic> data);
  Future<void> deleteDocument(String path);
  Future<DocumentReference> addDocument(
      String collectionPath, Map<String, dynamic> data);
  Stream<DocumentSnapshot<Map<String, dynamic>>> documentStream(String path);
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> queryStream(
    String path, {
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  });
  Future<T> runTransaction<T>(FutureOr<T> Function(Transaction) updateFunction);
  Future<int> collectionCount(
    String path, {
    List<WhereClause>? where,
    List<OrderBy>? orderBy,
    int? limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    DocumentSnapshot<Map<String, dynamic>>? endBefore,
  });
  Stream<int> collectionCountStream(String path, {List<WhereClause>? where});
  String generateId() {
    return const Uuid().v4();
  }
}

abstract class Transaction {
  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(String path);
  void setDocument(String path, Map<String, dynamic> data,
      {bool merge = false});
  void updateDocument(String path, Map<String, dynamic> data);
  void deleteDocument(String path);
}
