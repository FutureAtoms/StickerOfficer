import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/services/auth_service.dart';

import '../helpers/mock_secure_storage.dart';

void main() {
  group('AuthService', () {
    late MockSecureStorage mockStorage;

    setUp(() {
      mockStorage = MockSecureStorage();
    });

    test('getToken returns cached token when available', () async {
      mockStorage.data['jwt_token'] = 'cached-token';
      mockStorage.data['public_id'] = 'pub-123';

      final service = AuthService(
        baseUrl: 'http://localhost:8787',
        storage: mockStorage,
      );

      final token = await service.getToken();
      expect(token, 'cached-token');
    });

    test('publicId is populated after ensureRegistered', () async {
      mockStorage.data['jwt_token'] = 'tok';
      mockStorage.data['public_id'] = 'pub-abc';

      final service = AuthService(
        baseUrl: 'http://localhost:8787',
        storage: mockStorage,
      );

      await service.ensureRegistered();
      expect(service.publicId, 'pub-abc');
    });
  });
}
