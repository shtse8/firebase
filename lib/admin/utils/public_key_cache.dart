import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'cache.dart';

class PublicKeyCache {
  static final Cache<Map<String, String>> _cache =
      Cache<Map<String, String>>(const Duration(hours: 1));

  static Future<Map<String, String>> getKeys() async {
    return _cache.get(() async {
      final response = await http.get(Uri.parse(
          'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com'));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch public keys');
      }
      final keys = Map<String, String>.from(jsonDecode(response.body));
      return keys;
    });
  }

  static Future<RSAPublicKey> getKey(String kid) async {
    final keys = await getKeys();
    final certificate = keys[kid];
    if (certificate == null) {
      throw Exception('Invalid key ID');
    }
    return RSAPublicKey.cert(certificate);
  }

  static RSAPublicKey parsePublicKey(String pem) {
    return RSAPublicKey.cert(pem);
  }
}
