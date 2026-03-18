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
  /// use the default fake (200 + 4 bytes).
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

    // Default: return a tiny fake image (4 bytes).
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      ),
    );
  }
}

/// Helper to build a [Dio] instance wired to our [FakeInterceptor].
Dio _createFakeDio(FakeInterceptor interceptor) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api-inference.huggingface.co',
  ));
  dio.interceptors.add(interceptor);
  return dio;
}

void main() {
  // ---------------------------------------------------------------
  // 1. Construction
  // ---------------------------------------------------------------
  group('Construction', () {
    test('can be constructed with default Dio (no arguments)', () {
      // Should not throw.
      final service = HuggingFaceApiService();
      expect(service, isA<HuggingFaceApiService>());
    });

    test('can be constructed with a custom Dio instance', () {
      final customDio = Dio();
      final service = HuggingFaceApiService(dio: customDio);
      expect(service, isA<HuggingFaceApiService>());
    });
  });

  // ---------------------------------------------------------------
  // 2. _buildStickerPrompt adds proper sticker prefix
  // ---------------------------------------------------------------
  group('Sticker prompt construction', () {
    test('prompt sent to API contains sticker-style prefix and user input',
        () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'cute cat', count: 1);

      expect(interceptor.capturedRequests, hasLength(1));
      final body = interceptor.capturedRequests.first.data as Map;
      final inputs = body['inputs'] as String;

      expect(inputs, contains('sticker style'));
      expect(inputs, contains('die-cut sticker'));
      expect(inputs, contains('white outline border'));
      expect(inputs, contains('cartoon'));
      expect(inputs, contains('kawaii'));
      expect(inputs, contains('cute'));
      expect(inputs, contains('simple background'));
      expect(inputs, contains('high quality'));
      // User prompt appears at the end.
      expect(inputs, endsWith('cute cat'));
    });
  });

  // ---------------------------------------------------------------
  // 3. API key header handling
  // ---------------------------------------------------------------
  group('API key header', () {
    test('Authorization header is present when apiKey is provided', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(
        prompt: 'dog',
        apiKey: 'hf_test_key_123',
        count: 1,
      );

      final headers = interceptor.capturedRequests.first.headers;
      expect(headers['Authorization'], equals('Bearer hf_test_key_123'));
    });

    test('Authorization header is absent when apiKey is null', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'dog', count: 1);

      final headers = interceptor.capturedRequests.first.headers;
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  // ---------------------------------------------------------------
  // 4. Model selection
  // ---------------------------------------------------------------
  group('Model selection', () {
    test('uses default model when model parameter is null', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'flower', count: 1);

      final path = interceptor.capturedRequests.first.path;
      expect(
        path,
        contains('stabilityai/stable-diffusion-xl-base-1.0'),
      );
    });

    test('uses custom model when model parameter is specified', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(
        prompt: 'flower',
        count: 1,
        model: 'my-org/my-custom-model',
      );

      final path = interceptor.capturedRequests.first.path;
      expect(path, contains('my-org/my-custom-model'));
      expect(
        path,
        isNot(contains('stabilityai/stable-diffusion-xl-base-1.0')),
      );
    });
  });

  // ---------------------------------------------------------------
  // 5. Error handling — generation continues on individual failures
  // ---------------------------------------------------------------
  group('Error handling', () {
    test('continues generating when some requests fail', () async {
      int callIndex = 0;

      final interceptor = FakeInterceptor();
      interceptor.onRequest_ = (options) {
        final current = callIndex++;
        if (current == 1) {
          // Second request fails.
          throw Exception('network error');
        }
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: Uint8List.fromList([0x00, 0x01]),
        );
      };

      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(
        prompt: 'star',
        count: 3,
      );

      // 3 calls attempted, 1 failed => 2 successful results.
      expect(interceptor.capturedRequests, hasLength(3));
      expect(results, hasLength(2));
    });

    test('skips results with non-200 status codes', () async {
      final interceptor = FakeInterceptor();
      interceptor.onRequest_ = (options) {
        return Response(
          requestOptions: options,
          statusCode: 503,
          data: Uint8List(0),
        );
      };

      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(
        prompt: 'planet',
        count: 2,
      );

      expect(interceptor.capturedRequests, hasLength(2));
      expect(results, isEmpty);
    });
  });

  // ---------------------------------------------------------------
  // 6. Count parameter controls number of API calls
  // ---------------------------------------------------------------
  group('Count parameter', () {
    test('makes exactly count API calls (default = 4)', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'tree');

      expect(interceptor.capturedRequests, hasLength(4));
    });

    test('makes exactly count API calls (count = 1)', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'moon', count: 1);

      expect(interceptor.capturedRequests, hasLength(1));
    });

    test('makes exactly count API calls (count = 6)', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      await service.generateSticker(prompt: 'sun', count: 6);

      expect(interceptor.capturedRequests, hasLength(6));
    });

    test('returns matching number of successful results', () async {
      final interceptor = FakeInterceptor();
      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(
        prompt: 'rocket',
        count: 3,
      );

      expect(results, hasLength(3));
      for (final image in results) {
        expect(image, isA<Uint8List>());
        expect(image, isNotEmpty);
      }
    });
  });

  // ---------------------------------------------------------------
  // 7. Empty results when all requests fail
  // ---------------------------------------------------------------
  group('All requests fail', () {
    test('returns empty list when every request throws', () async {
      final interceptor = FakeInterceptor();
      interceptor.onRequest_ = (options) {
        throw Exception('server down');
      };

      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(
        prompt: 'galaxy',
        count: 4,
      );

      expect(results, isEmpty);
      // Still attempted all 4 calls.
      expect(interceptor.capturedRequests, hasLength(4));
    });

    test('returns empty list when every request returns non-200', () async {
      final interceptor = FakeInterceptor();
      interceptor.onRequest_ = (options) {
        return Response(
          requestOptions: options,
          statusCode: 500,
          data: Uint8List(0),
        );
      };

      final dio = _createFakeDio(interceptor);
      final service = HuggingFaceApiService(dio: dio);

      final results = await service.generateSticker(
        prompt: 'nebula',
        count: 3,
      );

      expect(results, isEmpty);
      expect(interceptor.capturedRequests, hasLength(3));
    });
  });
}
