import 'dart:io';

import 'service_account_credential.dart';

abstract class Credential {
  Map<String, dynamic> toJson();

  factory Credential.fromServiceAccount(File file) {
    return ServiceAccountCredential.fromFile(file);
  }
}
