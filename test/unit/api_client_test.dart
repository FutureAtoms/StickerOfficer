import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/services/api_client.dart';
import 'package:sticker_officer/services/auth_service.dart';

import '../helpers/mock_secure_storage.dart';

void main() {
  group('ApiClient', () {
    test('can be instantiated', () {
      final storage = MockSecureStorage();
      storage.data['jwt_token'] = 'test-token';
      storage.data['public_id'] = 'pub-1';

      final auth = AuthService(
        baseUrl: 'http://localhost:8787',
        storage: storage,
      );
      final client = ApiClient(
        baseUrl: 'http://localhost:8787',
        authService: auth,
      );

      expect(client, isNotNull);
    });
  });
}
