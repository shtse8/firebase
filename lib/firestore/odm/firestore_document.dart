import 'dart:async';
import 'dart:developer';
import 'package:json_diff/json_diff.dart';

import 'firestore_converter.dart';
import 'firestore_sdk_interface.dart';
import 'firestore_types.dart';
import 'package:collection/collection.dart';

abstract class FirestoreDocument<T> {
  final FirestoreSDK sdk;
  abstract final FirestoreConverter<T> converter;

  String get id => path.split('/').last;
  final String path;

  const FirestoreDocument(this.sdk, this.path);

  Future<DocumentSnapshot<T>> get() async {
    final snapshot = await sdk.getDocument(path);
    return DocumentSnapshot<T>(
      id: snapshot.id,
      data: snapshot.data != null ? converter.fromJson(snapshot.data!) : null,
      exists: snapshot.exists,
    );
  }

  Future<void> set(T data, {bool merge = false}) async {
    await sdk.setDocument(path, converter.toJson(data), merge: merge);
  }

  Future<void> update(
    T Function(DocumentSnapshot<T> currentSnapshot) updateFn, {
    bool noTransform = false,
  }) async {
    final currentSnapshot = await get();
    if (!currentSnapshot.exists) {
      throw Exception('Document does not exist');
    }

    final updatedData = updateFn(currentSnapshot);
    final currentMap = currentSnapshot.data != null
        ? converter.toJson(currentSnapshot.data as T)
        : <String, dynamic>{};
    final updatedMap = converter.toJson(updatedData);

    log('Updating currentMap: $currentMap');
    log('Updating updatedMap: $updatedMap');
    final updates =
        generateUpdates(currentMap, updatedMap, noTransform: noTransform);

    if (updates.isNotEmpty) {
      log('Updating document $path with updates: $updates');
      await sdk.updateDocument(path, updates);
    }
  }

  Future<void> delete() async {
    await sdk.deleteDocument(path);
  }

  Stream<DocumentSnapshot<T>> snapshot() {
    return sdk.documentStream(path).map(
          (snapshot) => DocumentSnapshot<T>(
            id: snapshot.id,
            data: snapshot.data != null
                ? converter.fromJson(snapshot.data!)
                : null,
            exists: snapshot.exists,
          ),
        );
  }

  static Map<String, dynamic> generateUpdates(
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData, {
    bool noTransform = false,
  }) {
    final differ = JsonDiffer.fromJson(oldData, newData);
    final updates = <String, dynamic>{};

    void processNode(DiffNode node) {
      String buildFieldPath(Object key) =>
          [...node.path, key.toString()].join('.');

      // Handle added fields
      node.added.forEach((key, value) {
        updates[buildFieldPath(key)] = value;
      });

      // Handle removed fields
      node.removed.forEach((key, _) {
        updates[buildFieldPath(key)] = FieldValue.delete();
      });

      // Handle changed fields
      node.changed.forEach((key, value) {
        final [oldValue, newValue] = value;
        final fieldPath = buildFieldPath(key);

        if (noTransform) {
          updates[fieldPath] = newValue;
        } else if (oldValue is List && newValue is List) {
          _handleListChanges(updates, fieldPath, oldValue, newValue);
        } else if (oldValue is num && newValue is num) {
          updates[fieldPath] = FieldValue.increment(newValue - oldValue);
        } else {
          updates[fieldPath] = newValue;
        }
      });

      // Process nested nodes
      node.node.forEach((key, value) {
        processNode(value);
      });
    }

    processNode(differ.diff());
    return updates;
  }

  static void _handleListChanges(Map<String, dynamic> updates, String fieldPath,
      List oldValue, List newValue) {
    const deepEq = DeepCollectionEquality();
    if (newValue.length > oldValue.length &&
        deepEq.equals(newValue.sublist(0, oldValue.length), oldValue)) {
      updates[fieldPath] =
          FieldValue.arrayUnion(newValue.sublist(oldValue.length));
    } else if (oldValue.length > newValue.length &&
        newValue.every((element) => oldValue.contains(element))) {
      final removedElements =
          oldValue.where((element) => !newValue.contains(element)).toList();
      updates[fieldPath] = FieldValue.arrayRemove(removedElements);
    } else if (!deepEq.equals(oldValue, newValue)) {
      updates[fieldPath] = newValue;
    }
  }
}
