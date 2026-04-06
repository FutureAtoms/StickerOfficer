enum AuthMethod { anonymous, google, apple }

class AuthUser {
  final String deviceId;
  final String publicId;
  final String token;
  final AuthMethod method;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  const AuthUser({
    required this.deviceId,
    required this.publicId,
    required this.token,
    this.method = AuthMethod.anonymous,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  bool get isAnonymous => method == AuthMethod.anonymous;
  bool get isSocial => method != AuthMethod.anonymous;

  AuthUser copyWith({
    String? deviceId,
    String? publicId,
    String? token,
    AuthMethod? method,
    String? displayName,
    String? email,
    String? photoUrl,
  }) {
    return AuthUser(
      deviceId: deviceId ?? this.deviceId,
      publicId: publicId ?? this.publicId,
      token: token ?? this.token,
      method: method ?? this.method,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
