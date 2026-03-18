import 'dart:typed_data';
import 'package:dio/dio.dart';

/// Hugging Face Inference API client for text-to-sticker generation
class HuggingFaceApiService {
  // In production, this key comes from Cloud Function proxy
  static const _baseUrl = 'https://api-inference.huggingface.co';
  static const _defaultModel = 'stabilityai/stable-diffusion-xl-base-1.0';

  final Dio _dio;

  HuggingFaceApiService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  /// Generate sticker images from a text prompt
  /// Returns up to [count] variations
  Future<List<Uint8List>> generateSticker({
    required String prompt,
    String? apiKey,
    int count = 4,
    String? model,
  }) async {
    final stickerPrompt = _buildStickerPrompt(prompt);
    final results = <Uint8List>[];

    for (int i = 0; i < count; i++) {
      try {
        final response = await _dio.post(
          '/models/${model ?? _defaultModel}',
          data: {
            'inputs': stickerPrompt,
            'parameters': {
              'seed': DateTime.now().millisecondsSinceEpoch + i,
              'num_inference_steps': 20,
              'guidance_scale': 7.5,
            },
          },
          options: Options(
            headers: {if (apiKey != null) 'Authorization': 'Bearer $apiKey'},
            responseType: ResponseType.bytes,
          ),
        );

        if (response.statusCode == 200) {
          results.add(Uint8List.fromList(response.data));
        }
      } catch (e) {
        // Skip failed generation, continue with others
      }
    }

    return results;
  }

  /// Build optimized prompt for sticker-style output
  String _buildStickerPrompt(String userPrompt) {
    return 'sticker style, die-cut sticker, white outline border, cartoon, '
        'kawaii, cute, simple background, high quality, $userPrompt';
  }
}
