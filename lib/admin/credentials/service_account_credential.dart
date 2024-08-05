import 'dart:convert';
import 'dart:io';
import 'credential.dart';

class ServiceAccountCredential implements Credential {
  final String type;
  final String projectId;
  final String privateKeyId;
  final String privateKey;
  final String clientEmail;
  final String clientId;
  final String authUri;
  final String tokenUri;
  final String authProviderX509CertUrl;
  final String clientX509CertUrl;

  ServiceAccountCredential({
    required this.type,
    required this.projectId,
    required this.privateKeyId,
    required this.privateKey,
    required this.clientEmail,
    required this.clientId,
    required this.authUri,
    required this.tokenUri,
    required this.authProviderX509CertUrl,
    required this.clientX509CertUrl,
  });

  factory ServiceAccountCredential.fromJson(Map<String, dynamic> json) {
    return ServiceAccountCredential(
      type: json['type'] as String,
      projectId: json['project_id'] as String,
      privateKeyId: json['private_key_id'] as String,
      privateKey: json['private_key'] as String,
      clientEmail: json['client_email'] as String,
      clientId: json['client_id'] as String,
      authUri: json['auth_uri'] as String,
      tokenUri: json['token_uri'] as String,
      authProviderX509CertUrl: json['auth_provider_x509_cert_url'] as String,
      clientX509CertUrl: json['client_x509_cert_url'] as String,
    );
  }

  factory ServiceAccountCredential.fromFile(File file) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ServiceAccountCredential.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'project_id': projectId,
        'private_key_id': privateKeyId,
        'private_key': privateKey,
        'client_email': clientEmail,
        'client_id': clientId,
        'auth_uri': authUri,
        'token_uri': tokenUri,
        'auth_provider_x509_cert_url': authProviderX509CertUrl,
        'client_x509_cert_url': clientX509CertUrl,
      };
}
