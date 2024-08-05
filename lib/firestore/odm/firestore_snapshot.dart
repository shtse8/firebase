class FirestoreDocumentSnapshot<T> {
  final String id;
  final T data;
  final bool exists;

  FirestoreDocumentSnapshot({
    required this.id,
    required this.data,
    required this.exists,
  });
}
