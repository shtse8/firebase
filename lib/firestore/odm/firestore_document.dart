import 'dart:async';
import 'package:json_diff/json_diff.dart';

import 'firestore_converter.dart';
import 'firestore_sdk_interface.dart';
import 'firestore_types.dart';

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
      T Function(DocumentSnapshot<T> currentSnapshot) updateFn) async {
    final currentSnapshot = await get();
    if (!currentSnapshot.exists) {
      throw Exception('Document does not exist');
    }

    final updatedData = updateFn(currentSnapshot);
    final currentMap = currentSnapshot.data != null
        ? converter.toJson(currentSnapshot.data as T)
        : <String, dynamic>{};
    final updatedMap = converter.toJson(updatedData);

    final diff = _diff(currentMap, updatedMap);

    if (diff.isNotEmpty) {
      await sdk.updateDocument(path, diff);
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

  static Map<String, dynamic> _diff(
      Map<String, dynamic> oldData, Map<String, dynamic> newData) {
    final differ = JsonDiffer.fromJson(oldData, newData);
    final result = <String, dynamic>{};

    void processNode(DiffNode node) {
      String getFullPath(Object key) => [...node.path, key].join('.');

      // Process added fields
      node.added.forEach((key, value) {
        result[getFullPath(key)] = newData[key];
      });

      // Process removed fields
      node.removed.forEach((key, _) {
        result[getFullPath(key)] = FieldValue.delete();
      });

      // Process changed fields
      node.changed.forEach((key, value) {
        final [oldValue, newValue] = value;
        final fullPath = getFullPath(key);

        if (oldValue is List && newValue is List) {
          _handleListChanges(result, fullPath, oldValue, newValue);
        } else if (oldValue is num && newValue is num) {
          result[fullPath] = FieldValue.increment(newValue - oldValue);
        } else {
          result[fullPath] = newValue;
        }
      });

      // Process nested nodes
      node.node.forEach((key, value) {
        processNode(value);
      });
    }

    processNode(differ.diff());
    return result;
  }

  static void _handleListChanges(
      Map<String, dynamic> result, String key, List oldValue, List newValue) {}
}
