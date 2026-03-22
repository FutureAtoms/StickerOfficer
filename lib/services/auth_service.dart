import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _cachedToken;
  String? _publicId;

  AuthService({required String baseUrl, FlutterSecureStorage? storage})
      : _dio = Dio(BaseOptions(baseUrl: baseUrl)),
        _storage = storage ?? const FlutterSecureStorage();

  Future<void> ensureRegistered() async {
    _cachedToken = await _storage.read(key: 'jwt_token');
    _publicId = await _storage.read(key: 'public_id');
    if (_cachedToken != null) return;

    var deviceId = await _storage.read(key: 'device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storage.write(key: 'device_id', value: deviceId);
    }

    final response =
        await _dio.post('/auth/register', data: {'device_id': deviceId});
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

    final response =
        await _dio.post('/auth/refresh', data: {'device_id': deviceId});
    _cachedToken = response.data['token'] as String;
    await _storage.write(key: 'jwt_token', value: _cachedToken!);
    return _cachedToken!;
  }

  Future<String> getToken() async {
    if (_cachedToken == null) await ensureRegistered();
    return _cachedToken!;
  }

  String? get publicId => _publicId;
}
