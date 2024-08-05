import 'package:meta/meta_meta.dart';
export '../firestore_odm.dart';
export '../firestore_collection.dart';
export '../firestore_document.dart';
export '../firestore_converter.dart';
export '../firestore_query.dart';
export '../firestore_sdk_interface.dart';
export '../firestore_types.dart';
export '../firestore_field.dart';

@Target({TargetKind.parameter})
class Unique {
  const Unique();
}

class Collection<T> {
  final String id;
  final List<Collection> subcollections;
  const Collection(this.id, [this.subcollections = const []]);
}

@Target({TargetKind.classType})
class FirestoreOdm {
  final List<Collection> collections;
  const FirestoreOdm(this.collections);
}
