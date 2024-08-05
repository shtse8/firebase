class DecodedToken {
  final String uid;
  final int exp;
  final int iat;
  final String aud;
  final String iss;
  final int authTime;

  DecodedToken({
    required this.uid,
    required this.exp,
    required this.iat,
    required this.aud,
    required this.iss,
    required this.authTime,
  });

  factory DecodedToken.fromPayload(Map<String, dynamic> payload) {
    return DecodedToken(
      uid: payload['sub'],
      exp: payload['exp'],
      iat: payload['iat'],
      aud: payload['aud'],
      iss: payload['iss'],
      authTime: payload['auth_time'],
    );
  }
}
