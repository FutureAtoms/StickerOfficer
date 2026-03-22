import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/services/huggingface_api.dart';

/// A fake [Interceptor] that captures outgoing requests and returns
/// configurable responses without hitting the network.
class FakeInterceptor extends Interceptor {
  final List<RequestOptions> capturedRequests = [];

  /// Controls per-request behaviour.  Return a [Response] to succeed,
  /// throw a [DioException] to simulate failure, or return `null` to
  /// use the default fake.
  Response Function(RequestOptions)? onRequest_;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedRequests.add(options);

    if (onRequest_ != null) {
      try {
        final response = onRequest_!(options);
        handler.resolve(response);
      } catch (e) {
        handler.reject(
          DioException(requestOptions: options, error: e),
        );
      }
      return;
    }

    // Default: return a JSON response with base64-encoded fake images.
    final fakeImage = base64Encode([0x89, 0x50, 0x4E, 0x47]);
    final count =
        (options.data as Map<String, dynamic>?)?['count'] as int? ?? 4;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'images': List.generate(count, (_) => fakeImage),
        },
      ),
    );
  }
}

/// Helper to build a [Dio] instance wired to our [FakeInterceptor].
Dio _createFakeDio(FakeInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8787'));
  dio.interceptors.add(interceptor);
  return dio;
}

void main() {
  group('Construction', () {
    test('can be constructed with default Dio (no arguments)', () {
      final service = HuggingFaceApiService();
      expect(service, isA<HuggingFaceApiService>());
    });

    test('can be constructed with a custom Dio instance', () {
      final customDio = Dio();
      final service = HuggingFaceApiService(dio: customDio);
      expect(service, isA<HuggingFaceApiService>());
    });
  });

  group('Worker proxy request', () {
    test('sends POST /generate with prompt and count', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'cute cat', count: 2);

      expect(interceptor.capturedRequests, hasLength(1));
      final req = interceptor.capturedRequests.first;
      expect(req.path, '/generate');
      expect(req.method, 'POST');

      final body = req.data as Map<String, dynamic>;
      expect(body['prompt'], 'cute cat');
      expect(body['count'], 2);
    });

    test('includes auth token header when provided', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(
        prompt: 'dog',
        authToken: 'test-jwt-token',
        count: 1,
      );

      final headers = interceptor.capturedRequests.first.headers;
      expect(headers['Authorization'], 'Bearer test-jwt-token');
    });

    test('omits auth header when token is null', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'dog', count: 1);

      final headers = interceptor.capturedRequests.first.headers;
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('Response parsing', () {
    test('decodes base64 images from JSON response', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(prompt: 'star', count: 3);

      expect(results, hasLength(3));
      for (final image in results) {
        expect(image, isA<Uint8List>());
        expect(image, isNotEmpty);
      }
    });

    test('returns empty list on error', () async {
      final interceptor = FakeInterceptor();
      interceptor.onRequest_ = (options) {
        throw Exception('server down');
      };

      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(prompt: 'galaxy', count: 4);
      expect(results, isEmpty);
    });

    test('returns empty list on non-200 status', () async {
      final interceptor = FakeInterceptor();
      interceptor.onRequest_ = (options) {
        return Response(
          requestOptions: options,
          statusCode: 429,
          data: {'error': 'rate limited'},
        );
      };

      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results =
          await service.generateSticker(prompt: 'nebula', count: 2);
      expect(results, isEmpty);
    });
  });

  group('Model parameter', () {
    test('includes model in request when specified', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(
        prompt: 'flower',
        count: 1,
        model: 'custom/model',
      );

      final body =
          interceptor.capturedRequests.first.data as Map<String, dynamic>;
      expect(body['model'], 'custom/model');
    });

    test('omits model when not specified', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'flower', count: 1);

      final body =
          interceptor.capturedRequests.first.data as Map<String, dynamic>;
      expect(body.containsKey('model'), isFalse);
    });
  });
}
