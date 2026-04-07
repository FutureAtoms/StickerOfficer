import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// AI sticker generation via Cloudflare Worker proxy.
/// The Worker handles API key management, prompt filtering,
/// and rate limiting.
class HuggingFaceApiService {
  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sticker-officer-api.ceofutureatoms.workers.dev',
  );

  final Dio _dio;

  HuggingFaceApiService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? _defaultBaseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
            ),
          );

  /// Generate sticker images from a text prompt via Worker proxy.
  /// Returns base64-decoded images as Uint8List.
  Future<List<Uint8List>> generateSticker({
    required String prompt,
    String? authToken,
    int count = 4,
    String? model,
  }) async {
    try {
      final response = await _dio.post(
        '/generate',
        data: {
          'prompt': prompt,
          'count': count,
          if (model != null) 'model': model,
        },
        options: Options(
          headers: {
            if (authToken != null) 'Authorization': 'Bearer $authToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final images = (data['images'] as List<dynamic>?) ?? [];
        return images.map((b64) => base64Decode(b64 as String)).toList();
      }
    } catch (e) {
      // Generation failed — return empty
    }

    return [];
  }
}
