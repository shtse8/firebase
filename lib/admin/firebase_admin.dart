import 'dart:convert';
import 'dart:developer';

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'credentials/credential.dart';
import 'credentials/service_account_credential.dart';

class LoggingClient extends http.BaseClient {
  final http.Client _inner;
  final void Function(String) _logCallback;

  LoggingClient(this._inner, this._logCallback);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Log the outgoing request
    _logCallback('Outgoing request: ${request.method} ${request.url}');
    _logCallback('Headers: ${request.headers}');
    if (request is http.Request) {
      _logCallback('Body: ${request.body}');
    }

    final response = await _inner.send(request);

    // Log the incoming response
    _logCallback('Incoming response: ${response.statusCode}');
    _logCallback('Headers: ${response.headers}');

    // Create a copy of the stream so we can read it for logging
    final bytes = await response.stream.toBytes();
    final responseBody = utf8.decode(bytes);
    _logCallback('Body: $responseBody');

    // Return a new StreamedResponse with the original data
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

class FirebaseScopes {
  // For Firestore and general Google Cloud Platform services
  static const String cloudPlatform = FirestoreApi.cloudPlatformScope;

  // For Firebase Authentication
  static const String firebaseAuth =
      'https://www.googleapis.com/auth/firebase.auth';

  // For Identity Toolkit (often used with Firebase Auth)
  static const String identityToolkit =
      'https://www.googleapis.com/auth/identitytoolkit';

  // For Firebase Realtime Database
  static const String firebaseDatabase =
      'https://www.googleapis.com/auth/firebase.database';

  // For accessing user email information
  static const String userInfoEmail =
      'https://www.googleapis.com/auth/userinfo.email';

  // For Firebase Cloud Messaging
  static const String firebaseMessaging =
      'https://www.googleapis.com/auth/firebase.messaging';

  // Commonly used scope combination for Firebase Admin SDK
  static const List<String> firebaseAdminScopes = [
    cloudPlatform,
    // firebaseAuth,
    identityToolkit,
    firebaseDatabase,
    userInfoEmail,
    firebaseMessaging,
  ];
}

class FirebaseAdminApp {
  final String projectId;
  final ServiceAccountCredentials credentials;
  late final http.Client client;

  FirebaseAdminApp._(this.projectId, this.credentials, this.client);

  static Future<FirebaseAdminApp> initializeApp(Credential credential) async {
    if (credential is! ServiceAccountCredential) {
      throw Exception('Unsupported credential type');
    }

    final credentials = ServiceAccountCredentials.fromJson(credential.toJson());

    final client = await clientViaServiceAccount(
        credentials, FirebaseScopes.firebaseAdminScopes);

    return FirebaseAdminApp._(
        credential.projectId, credentials, LoggingClient(client, log));
  }
}
