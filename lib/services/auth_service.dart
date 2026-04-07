import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../data/models/auth_user.dart';

class AuthService {
  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _cachedToken;
  String? _publicId;
  String? _deviceId;

  AuthService({required String baseUrl, FlutterSecureStorage? storage})
    : _dio = Dio(BaseOptions(baseUrl: baseUrl)),
      _storage = storage ?? const FlutterSecureStorage();

  Future<void> ensureRegistered() async {
    _cachedToken = await _storage.read(key: 'jwt_token');
    _publicId = await _storage.read(key: 'public_id');
    _deviceId = await _storage.read(key: 'device_id');
    if (_cachedToken != null) return;

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await _storage.write(key: 'device_id', value: _deviceId!);
    }

    final response = await _dio.post(
      '/auth/register',
      data: {'device_id': _deviceId},
    );
    _cachedToken = response.data['token'] as String;
    _publicId = response.data['public_id'] as String;
    await _storage.write(key: 'jwt_token', value: _cachedToken!);
    await _storage.write(key: 'public_id', value: _publicId!);
  }

  Future<String> refreshToken() async {
    final deviceId = await _storage.read(key: 'device_id');
    if (deviceId == null) {
      throw StateError('No device_id found — call ensureRegistered first');
    }

    final response = await _dio.post(
      '/auth/refresh',
      data: {'device_id': deviceId},
    );
    _cachedToken = response.data['token'] as String;
    await _storage.write(key: 'jwt_token', value: _cachedToken!);
    return _cachedToken!;
  }

  Future<String> getToken() async {
    if (_cachedToken == null) await ensureRegistered();
    return _cachedToken!;
  }

  String? get publicId => _publicId;

  /// Sign in with Google. Sends the Google ID token to the Worker,
  /// which verifies it and links/creates the account.
  Future<AuthUser> signInWithGoogle(String idToken) async {
    final deviceId = await _storage.read(key: 'device_id');
    final response = await _dio.post(
      '/auth/google',
      data: {'id_token': idToken, if (deviceId != null) 'device_id': deviceId},
    );

    final data = response.data as Map<String, dynamic>;

    // The server may return a DIFFERENT device_id if this Google account
    // was previously linked from another device (cross-device sign-in).
    final canonicalDeviceId = data['device_id'] as String;
    _cachedToken = data['token'] as String;
    _publicId = data['public_id'] as String;
    _deviceId = canonicalDeviceId;

    await _storage.write(key: 'device_id', value: canonicalDeviceId);
    await _storage.write(key: 'jwt_token', value: _cachedToken!);
    await _storage.write(key: 'public_id', value: _publicId!);
    await _storage.write(key: 'auth_method', value: 'google');
    await _storage.write(
      key: 'display_name',
      value: data['google_name'] as String? ?? '',
    );
    await _storage.write(
      key: 'email',
      value: data['google_email'] as String? ?? '',
    );
    await _storage.write(
      key: 'photo_url',
      value: data['google_photo'] as String? ?? '',
    );

    return getAuthUser();
  }

  /// Sign in with Apple. Sends the Apple identity token to the Worker.
  /// [fullName] should be provided on the first authorization (Apple only
  /// sends the name once).
  Future<AuthUser> signInWithApple(
    String identityToken, {
    String? fullName,
    String? rawNonce,
  }) async {
    final deviceId = await _storage.read(key: 'device_id');
    final response = await _dio.post(
      '/auth/apple',
      data: {
        'identity_token': identityToken,
        if (deviceId != null) 'device_id': deviceId,
        if (fullName != null) 'full_name': fullName,
        if (rawNonce != null) 'nonce': rawNonce,
      },
    );

    final data = response.data as Map<String, dynamic>;

    final canonicalDeviceId = data['device_id'] as String;
    _cachedToken = data['token'] as String;
    _publicId = data['public_id'] as String;
    _deviceId = canonicalDeviceId;

    await _storage.write(key: 'device_id', value: canonicalDeviceId);
    await _storage.write(key: 'jwt_token', value: _cachedToken!);
    await _storage.write(key: 'public_id', value: _publicId!);
    await _storage.write(key: 'auth_method', value: 'apple');
    await _storage.write(
      key: 'display_name',
      value: data['apple_name'] as String? ?? '',
    );
    await _storage.write(
      key: 'email',
      value: data['apple_email'] as String? ?? '',
    );
    // Apple doesn't provide a photo URL
    await _storage.delete(key: 'photo_url');

    return getAuthUser();
  }

  /// Disconnect the social provider. Keeps the same device_id/token/publicId
  /// so all user data (packs, likes, votes) remains intact.
  Future<void> disconnectProvider() async {
    await _storage.write(key: 'auth_method', value: 'anonymous');
    await _storage.delete(key: 'display_name');
    await _storage.delete(key: 'email');
    await _storage.delete(key: 'photo_url');
  }

  /// Read all cached auth state from secure storage.
  Future<AuthUser> getAuthUser() async {
    final token = _cachedToken ?? await _storage.read(key: 'jwt_token') ?? '';
    final publicId = _publicId ?? await _storage.read(key: 'public_id') ?? '';
    final deviceId = _deviceId ?? await _storage.read(key: 'device_id') ?? '';
    final methodStr = await _storage.read(key: 'auth_method') ?? 'anonymous';
    final displayName = await _storage.read(key: 'display_name');
    final email = await _storage.read(key: 'email');
    final photoUrl = await _storage.read(key: 'photo_url');

    AuthMethod method;
    switch (methodStr) {
      case 'google':
        method = AuthMethod.google;
        break;
      case 'apple':
        method = AuthMethod.apple;
        break;
      default:
        method = AuthMethod.anonymous;
    }

    return AuthUser(
      deviceId: deviceId,
      publicId: publicId,
      token: token,
      method: method,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
    );
  }
}
