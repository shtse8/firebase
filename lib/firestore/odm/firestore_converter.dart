abstract interface class FirestoreConverter<T> {
  T fromJson(Map<String, dynamic> data);
  Map<String, dynamic> toJson(T value);
}
