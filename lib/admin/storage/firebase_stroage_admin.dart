import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:mime/mime.dart';
import '../firebase_admin.dart';

class FirebaseStorageAdmin {
  final FirebaseAdminApp _app;
  final String _bucket;
  late storage.StorageApi _storageApi;

  FirebaseStorageAdmin._(this._app, this._bucket) {
    _storageApi = storage.StorageApi(_app.client);
  }

  static FirebaseStorageAdmin instanceFor(FirebaseAdminApp app,
      {String? bucket}) {
    final storageBucket = bucket ?? '${app.projectId}.appspot.com';
    return FirebaseStorageAdmin._(app, storageBucket);
  }

  String get bucket => _bucket;

  Reference ref([String? path]) {
    return Reference._(this, path ?? '');
  }
}

class Reference {
  final FirebaseStorageAdmin _storage;
  final String _path;

  Reference._(this._storage, this._path);

  String get bucket => _storage.bucket;
  String get fullPath => _path;
  String get name => _path.split('/').last;

  Reference child(String path) {
    final newPath = this._path.isEmpty ? path : '${this._path}/$path';
    return Reference._(_storage, newPath);
  }

  Reference? get parent {
    final segments = _path.split('/');
    if (segments.length > 1) {
      segments.removeLast();
      return Reference._(_storage, segments.join('/'));
    }
    return null;
  }

  Future<String> getDownloadURL() async {
    final object =
        await _storage._storageApi.objects.get(bucket, _path) as storage.Object;
    if (object.mediaLink == null || object.mediaLink!.isEmpty) {
      throw FirebaseStorageException(
          "No download URL available for object at path: $_path",
          code: "no-download-url");
    }
    return object.mediaLink!;
  }

  Future<UploadTask> putData(Uint8List data, {SettableMetadata? metadata}) {
    final uploadTask = UploadTask._(_storage, _path, data, metadata);
    return Future.value(uploadTask);
  }

  Future<UploadTask> putFile(File file, {SettableMetadata? metadata}) async {
    final data = await file.readAsBytes();
    final contentType = metadata?.contentType ?? lookupMimeType(file.path);
    return putData(data,
        metadata: SettableMetadata(
          contentType: contentType,
          cacheControl: metadata?.cacheControl,
          contentDisposition: metadata?.contentDisposition,
          contentEncoding: metadata?.contentEncoding,
          contentLanguage: metadata?.contentLanguage,
          customMetadata: metadata?.customMetadata,
        ));
  }

  Future<UploadTask> putString(String data,
      {PutStringFormat format = PutStringFormat.raw,
      SettableMetadata? metadata}) {
    late Uint8List bytes;
    switch (format) {
      case PutStringFormat.raw:
        bytes = Uint8List.fromList(utf8.encode(data));
        break;
      case PutStringFormat.base64:
        bytes = base64.decode(data);
        break;
      case PutStringFormat.base64Url:
        bytes = base64Url.decode(data);
        break;
      case PutStringFormat.dataUrl:
        final matches = RegExp(r'^data:([^;]+);base64,(.*)$').firstMatch(data);
        if (matches != null) {
          bytes = base64.decode(matches.group(2)!);
          metadata ??= SettableMetadata();
          metadata.contentType = matches.group(1);
        } else {
          throw ArgumentError('Invalid data URL');
        }
        break;
    }
    return putData(bytes, metadata: metadata);
  }

  Future<void> delete() async {
    await _storage._storageApi.objects.delete(bucket, _path);
  }

  Future<FullMetadata> getMetadata() async {
    final object =
        await _storage._storageApi.objects.get(bucket, _path) as storage.Object;
    return FullMetadata.fromStorageObject(object);
  }

  Future<FullMetadata> updateMetadata(SettableMetadata metadata) async {
    final updatedObject = await _storage._storageApi.objects.patch(
      metadata.toStorageObject(),
      bucket,
      _path,
    );
    return FullMetadata.fromStorageObject(updatedObject);
  }

  Future<ListResult> list({int? maxResults, String? pageToken}) async {
    final objects = await _storage._storageApi.objects.list(
      bucket,
      prefix: _path,
      maxResults: maxResults,
      pageToken: pageToken,
    );
    return ListResult.fromObjects(this, objects);
  }

  Future<Uint8List> getData({int? maxSize}) async {
    final media = await _storage._storageApi.objects.get(
      bucket,
      _path,
      downloadOptions: storage.DownloadOptions.fullMedia,
    ) as storage.Media;

    final bytes = await media.stream.toList();
    final data = bytes.expand((x) => x).toList();
    if (maxSize != null && data.length > maxSize) {
      throw Exception('Downloaded data exceeds maximum size');
    }
    return Uint8List.fromList(data);
  }
}

class UploadTask {
  final FirebaseStorageAdmin _storage;
  final String _path;
  final Uint8List _data;
  final SettableMetadata? _metadata;

  UploadTask._(this._storage, this._path, this._data, this._metadata);

  Future<UploadTaskSnapshot> _start() async {
    final media = storage.Media(Stream.value(_data), _data.length);
    final object = storage.Object()
      ..name = _path
      ..metadata = _metadata?.customMetadata;

    final uploadedObject = await _storage._storageApi.objects.insert(
      object,
      _storage.bucket,
      uploadMedia: media,
    );

    final metadata = FullMetadata.fromStorageObject(uploadedObject);
    return UploadTaskSnapshot(metadata, _data.length, TaskState.success);
  }

  Stream<UploadTaskSnapshot> get snapshotEvents {
    return Stream.fromFuture(_start());
  }

  Future<UploadTaskSnapshot> get snapshot => _start();
}

class UploadTaskSnapshot {
  final FullMetadata metadata;
  final int bytesTransferred;
  final TaskState state;

  UploadTaskSnapshot(this.metadata, this.bytesTransferred, this.state);
}

class SettableMetadata {
  final String? cacheControl;
  final String? contentDisposition;
  final String? contentEncoding;
  final String? contentLanguage;
  String? contentType;
  final Map<String, String>? customMetadata;

  SettableMetadata({
    this.cacheControl,
    this.contentDisposition,
    this.contentEncoding,
    this.contentLanguage,
    this.contentType,
    this.customMetadata,
  });

  Map<String, String> toMap() {
    return {
      if (cacheControl != null) 'cacheControl': cacheControl!,
      if (contentDisposition != null) 'contentDisposition': contentDisposition!,
      if (contentEncoding != null) 'contentEncoding': contentEncoding!,
      if (contentLanguage != null) 'contentLanguage': contentLanguage!,
      if (contentType != null) 'contentType': contentType!,
      if (customMetadata != null) ...customMetadata!,
    };
  }

  storage.Object toStorageObject() {
    return storage.Object()
      ..cacheControl = cacheControl
      ..contentDisposition = contentDisposition
      ..contentEncoding = contentEncoding
      ..contentLanguage = contentLanguage
      ..contentType = contentType
      ..metadata = customMetadata;
  }
}

class FullMetadata extends SettableMetadata {
  final String bucket;
  final String generation;
  final String metageneration;
  final String name;
  final int size;
  final DateTime timeCreated;
  final DateTime updated;
  final String md5Hash;

  FullMetadata({
    required this.bucket,
    required this.generation,
    required this.metageneration,
    required this.name,
    required this.size,
    required this.timeCreated,
    required this.updated,
    required this.md5Hash,
    String? cacheControl,
    String? contentDisposition,
    String? contentEncoding,
    String? contentLanguage,
    String? contentType,
    Map<String, String>? customMetadata,
  }) : super(
          cacheControl: cacheControl,
          contentDisposition: contentDisposition,
          contentEncoding: contentEncoding,
          contentLanguage: contentLanguage,
          contentType: contentType,
          customMetadata: customMetadata,
        );

  factory FullMetadata.fromStorageObject(storage.Object object) {
    return FullMetadata(
      bucket: object.bucket ?? '',
      generation: object.generation ?? '',
      metageneration: object.metageneration ?? '',
      name: object.name ?? '',
      size: int.parse(object.size ?? '0'),
      timeCreated: object.timeCreated ?? DateTime.now(),
      updated: object.updated ?? DateTime.now(),
      md5Hash: object.md5Hash ?? '',
      cacheControl: object.cacheControl,
      contentDisposition: object.contentDisposition,
      contentEncoding: object.contentEncoding,
      contentLanguage: object.contentLanguage,
      contentType: object.contentType,
      customMetadata: object.metadata,
    );
  }
}

class ListResult {
  final List<Reference> items;
  final List<Reference> prefixes;
  final String? nextPageToken;

  ListResult({
    required this.items,
    required this.prefixes,
    this.nextPageToken,
  });

  factory ListResult.fromObjects(Reference parent, storage.Objects objects) {
    final items = (objects.items ?? [])
        .map((item) => Reference._(parent._storage, item.name ?? ''))
        .toList();

    final prefixes = (objects.prefixes ?? [])
        .map((prefix) => Reference._(parent._storage, prefix))
        .toList();

    return ListResult(
      items: items,
      prefixes: prefixes,
      nextPageToken: objects.nextPageToken,
    );
  }
}

enum TaskState { running, paused, success, canceled, error }

enum PutStringFormat { raw, base64, base64Url, dataUrl }

class FirebaseStorageException implements Exception {
  final String message;
  final String code;

  FirebaseStorageException(this.message, {required this.code});

  @override
  String toString() => "FirebaseStorageException: $message (Code: $code)";
}
