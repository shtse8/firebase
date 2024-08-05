import 'dart:async';

class CacheItem<T> {
  final T value;
  final DateTime expiry;

  CacheItem(this.value, this.expiry);

  bool get isExpired => DateTime.now().isAfter(expiry);
}

class Cache<T> {
  final Duration duration;
  CacheItem<T>? _cacheItem;

  Cache(this.duration);

  Future<T> get(Future<T> Function() fetcher) async {
    if (_cacheItem == null || _cacheItem!.isExpired) {
      final value = await fetcher();
      _cacheItem = CacheItem(value, DateTime.now().add(duration));
    }
    return _cacheItem!.value;
  }

  void clear() {
    _cacheItem = null;
  }
}
