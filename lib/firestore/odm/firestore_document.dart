import 'dart:async';
import 'dart:developer';

import 'firestore_converter.dart';
import 'firestore_sdk_interface.dart';
import 'firestore_types.dart';
import 'package:collection/collection.dart';

sealed class DiffChange {
  const DiffChange();
}

class AddedChange extends DiffChange {
  final dynamic value;
  const AddedChange(this.value);
}

class RemovedChange extends DiffChange {
  final dynamic value;
  const RemovedChange(this.value);
}

class ModifiedChange extends DiffChange {
  final dynamic oldValue;
  final dynamic newValue;
  const ModifiedChange(this.oldValue, this.newValue);
}

class MovedChange extends DiffChange {
  final int oldIndex;
  final int newIndex;
  const MovedChange(this.oldIndex, this.newIndex);
}

class NestedChange extends DiffChange {
  final DiffNode node;
  const NestedChange(this.node);
}

class ArrayUnionChange extends DiffChange {
  final List union;
  const ArrayUnionChange(this.union);
}

class ArrayRemoveChange extends DiffChange {
  final List remove;
  const ArrayRemoveChange(this.remove);
}

class DiffNode {
  DiffNode(this.path);

  final List<Object> path;
  final Map<Object, DiffChange> changes = {};

  void addChange(Object key, DiffChange change) {
    changes[key] = change;
  }

  bool get hasChanges => changes.isNotEmpty;

  @override
  String toString() => 'DiffNode(path: $path, changes: $changes)';
}

class JsonDiffer {
  static final _deepEquality = DeepCollectionEquality();

  static DiffNode diff(Map leftJson, Map rightJson,
      {bool treatArrayAsValue = false}) {
    return _compareMaps(leftJson, rightJson, [], treatArrayAsValue);
  }

  static DiffNode _compareMaps(
      Map left, Map right, List<Object> path, bool treatArrayAsValue) {
    final diffNode = DiffNode(path);

    for (final key in left.keys) {
      if (!right.containsKey(key)) {
        diffNode.addChange(key, RemovedChange(left[key]));
      } else {
        final leftValue = left[key];
        final rightValue = right[key];
        if (leftValue is Map && rightValue is Map) {
          final childDiff = _compareMaps(
              leftValue, rightValue, [...path, key], treatArrayAsValue);
          if (childDiff.hasChanges) {
            diffNode.addChange(key, NestedChange(childDiff));
          }
        } else if (leftValue is List && rightValue is List) {
          if (treatArrayAsValue) {
            final arrayChange = _compareArraysAsValues(leftValue, rightValue);
            if (arrayChange != null) {
              diffNode.addChange(key, arrayChange);
            }
          } else {
            final childDiff =
                _compareLists(leftValue, rightValue, [...path, key]);
            if (childDiff.hasChanges) {
              diffNode.addChange(key, NestedChange(childDiff));
            }
          }
        } else if (!_deepEquality.equals(leftValue, rightValue)) {
          diffNode.addChange(key, ModifiedChange(leftValue, rightValue));
        }
      }
    }

    for (final key in right.keys) {
      if (!left.containsKey(key)) {
        diffNode.addChange(key, AddedChange(right[key]));
      }
    }

    return diffNode;
  }

  static DiffNode _compareLists(List left, List right, List<Object> path) {
    final diffNode = DiffNode(path);
    final len = left.length > right.length ? left.length : right.length;

    for (var i = 0; i < len; i++) {
      if (i >= left.length) {
        diffNode.addChange(i, AddedChange(right[i]));
      } else if (i >= right.length) {
        diffNode.addChange(i, RemovedChange(left[i]));
      } else {
        final leftValue = left[i];
        final rightValue = right[i];
        if (leftValue is Map && rightValue is Map) {
          final childDiff =
              _compareMaps(leftValue, rightValue, [...path, i], false);
          if (childDiff.hasChanges) {
            diffNode.addChange(i, NestedChange(childDiff));
          }
        } else if (leftValue is List && rightValue is List) {
          final childDiff = _compareLists(leftValue, rightValue, [...path, i]);
          if (childDiff.hasChanges) {
            diffNode.addChange(i, NestedChange(childDiff));
          }
        } else if (!_deepEquality.equals(leftValue, rightValue)) {
          diffNode.addChange(i, ModifiedChange(leftValue, rightValue));
        }
      }
    }

    _detectMovedItems(left, right, diffNode);

    return diffNode;
  }

  static DiffChange? _compareArraysAsValues(List left, List right) {
    if (_deepEquality.equals(left, right)) {
      return null;
    }

    if (right.length > left.length &&
        left.isNotEmpty &&
        _deepEquality.equals(left, right.sublist(0, left.length))) {
      return ArrayUnionChange(right.sublist(left.length));
    }

    if (left.length > right.length &&
        right.isNotEmpty &&
        _deepEquality.equals(right, left.sublist(0, right.length))) {
      return ArrayRemoveChange(left.sublist(right.length));
    }

    return ModifiedChange(left, right);
  }

  static void _detectMovedItems(List left, List right, DiffNode diffNode) {
    final leftIndexMap = <dynamic, int>{};
    for (var i = 0; i < left.length; i++) {
      leftIndexMap[left[i]] = i;
    }

    for (var newIndex = 0; newIndex < right.length; newIndex++) {
      final item = right[newIndex];
      if (leftIndexMap.containsKey(item)) {
        final oldIndex = leftIndexMap[item]!;
        if (oldIndex != newIndex) {
          diffNode.addChange(oldIndex, MovedChange(oldIndex, newIndex));
        }
      }
    }
  }
}

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

    final updates =
        generateUpdates(currentMap, updatedMap, noTransform: noTransform);

    if (updates.isNotEmpty) {
      // log('Updating document $path:\ncurrentMap: $currentMap\nupdatedMap: $updatedMap\nupdates: $updates');
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
    final updates = <String, dynamic>{};

    void processNode(DiffNode node) {
      String buildFieldPath(Object key) =>
          [...node.path, key.toString()].join('.');

      node.changes.forEach((key, change) {
        final fieldPath = buildFieldPath(key);
        switch (change) {
          case AddedChange addedChange:
            updates[fieldPath] = addedChange.value;
            break;
          case RemovedChange _:
            updates[fieldPath] = FieldValue.delete();
            break;
          case ModifiedChange modifiedChange:
            if (noTransform) {
              updates[fieldPath] = modifiedChange.newValue;
            } else if (modifiedChange.oldValue is num &&
                modifiedChange.newValue is num) {
              updates[fieldPath] = FieldValue.increment(
                  modifiedChange.newValue - modifiedChange.oldValue);
            } else {
              updates[fieldPath] = modifiedChange.newValue;
            }
            break;
          case MovedChange _:
            // Do nothing for moved items
            break;
          case NestedChange change:
            processNode(change.node);
            break;
          case ArrayUnionChange arrayUnionChange:
            updates[fieldPath] = FieldValue.arrayUnion(arrayUnionChange.union);
            break;
          case ArrayRemoveChange arrayRemoveChange:
            updates[fieldPath] =
                FieldValue.arrayRemove(arrayRemoveChange.remove);
            break;
        }
      });
    }

    final node = JsonDiffer.diff(oldData, newData, treatArrayAsValue: true);
    processNode(node);
    return updates;
  }
}
