import 'dart:async';

import 'firestore_document.dart';
import 'firestore_query.dart';

abstract class FirestoreCollection<T> extends FirestoreQuery<T> {
  const FirestoreCollection(super.sdk, super.path);

  FirestoreDocument<T> doc([String? id]) {
    final docId = id ?? sdk.generateId();
    final docPath = '$path/$docId';
    return getDocument(docPath);
  }

  Future<FirestoreDocument<T>> add(T data) async {
    final docRef = await sdk.addDocument(path, converter.toJson(data));
    return getDocument(docRef.path);
  }

  FirestoreDocument<T> getDocument(String path);
}
