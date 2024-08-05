import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../firebase_admin.dart';
import 'decoded_token.dart';
import '../utils/public_key_cache.dart';

class FirebaseAuthAdmin {
  final FirebaseAdminApp app;

  FirebaseAuthAdmin._(this.app);

  static FirebaseAuthAdmin instanceFor(FirebaseAdminApp app) {
    return FirebaseAuthAdmin._(app);
  }

  Future<DecodedToken> verifyIdToken(String idToken,
      {bool checkRevoked = false}) async {
    // Decode the token without verifying the signature to access the header and payload
    final jwt = JWT.decode(idToken);

    // Verify the header
    final header = jwt.header;
    if (header == null || header['alg'] != 'RS256') {
      throw Exception('Invalid token algorithm');
    }

    // Get the public key for the token's kid
    final kid = header['kid'];
    if (kid == null) {
      throw Exception('Missing key ID');
    }
    final publicKey = await PublicKeyCache.getKey(kid);

    // Verify the token with the public key and built-in checks
    try {
      JWT.verify(
        idToken,
        publicKey,
        audience: Audience.one(app.projectId),
        issuer: 'https://securetoken.google.com/${app.projectId}',
      );
    } catch (e) {
      throw Exception('Invalid token signature');
    }

    // Verify the payload
    final payload = jwt.payload;

    if (payload['sub']?.isEmpty ?? true) {
      throw Exception('Invalid subject');
    }

    if (checkRevoked) {
      await _checkIfRevoked(payload['sub'], payload['iat']);
    }

    return DecodedToken.fromPayload(payload);
  }

  Future<void> _checkIfRevoked(String uid, int issuedAt) async {
    final response = await app.client.post(
      Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:lookup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'localId': [uid]
      }),
    );

    if (response.statusCode != 200) {
      final errorResponse = jsonDecode(response.body);
      throw Exception(
          'Failed to fetch user data: ${errorResponse['error']['message']}');
    }

    final userData = jsonDecode(response.body);
    if (userData['users'] == null || userData['users'].isEmpty) {
      throw Exception('User not found');
    }

    final lastRefreshAt = userData['users'][0]['lastRefreshAt'] as String?;
    if (lastRefreshAt == null) {
      throw Exception('lastRefreshAt is missing');
    }

    final lastRefreshEpoch =
        DateTime.parse(lastRefreshAt).millisecondsSinceEpoch ~/ 1000;

    if (issuedAt < lastRefreshEpoch) {
      throw Exception('Token has been revoked');
    }
  }
}
