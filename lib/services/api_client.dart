import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'auth_service.dart';

class ApiClient {
  final Dio _dio;
  final AuthService _authService;

  ApiClient({required String baseUrl, required AuthService authService})
    : _authService = authService,
      _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authService.getToken();
          options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            try {
              final newToken = await _authService.refreshToken();
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (_) {
              return handler.next(error);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  // Feed
  Future<Map<String, dynamic>> getFeed({int page = 1}) async {
    final r = await _dio.get('/feed', queryParameters: {'page': page});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getRecent({int page = 1}) async {
    final r = await _dio.get('/feed/recent', queryParameters: {'page': page});
    return r.data as Map<String, dynamic>;
  }

  // Packs
  Future<Map<String, dynamic>> publishPack({
    required String name,
    required String category,
    required List<String> tags,
    required List<Map<String, String>> stickers,
  }) async {
    final r = await _dio.post(
      '/packs',
      data: {
        'name': name,
        'category': category,
        'tags': tags,
        'stickers': stickers,
      },
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> likePack(String id) async {
    final r = await _dio.post('/packs/$id/like');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> downloadPack(String id) async {
    final r = await _dio.post('/packs/$id/download');
    return r.data as Map<String, dynamic>;
  }

  // Challenges
  Future<Map<String, dynamic>> getChallenges() async {
    final r = await _dio.get('/challenges');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitChallenge({
    required String challengeId,
    required String packId,
  }) async {
    final r = await _dio.post(
      '/challenges/$challengeId/submit',
      data: {'pack_id': packId},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> vote({
    required String challengeId,
    required String submissionId,
  }) async {
    final r = await _dio.post(
      '/challenges/$challengeId/vote',
      data: {'submission_id': submissionId},
    );
    return r.data as Map<String, dynamic>;
  }

  // Moderation
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    await _dio.post(
      '/report',
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        if (details != null) 'details': details,
      },
    );
  }

  Future<void> blockUser(String publicId) async {
    await _dio.post('/block/$publicId');
  }

  Future<void> acceptTerms() async {
    await _dio.post('/auth/accept-terms');
  }

  // Background Removal (server-side RMBG-2.0 via HuggingFace)
  Future<Uint8List?> removeBackground(Uint8List imageBytes) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final r = await _dio.post(
        '/remove-bg',
        data: {'image': base64Image},
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final resultBase64 = r.data['image'] as String?;
      if (resultBase64 == null) return null;
      return base64Decode(resultBase64);
    } on DioException catch (e) {
      if (e.response?.statusCode == 503) {
        // Model is loading — throw a specific message
        throw Exception(
          'AI model is warming up, please try again in a few seconds',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Profile
  Future<Map<String, dynamic>> getProfile(String publicId) async {
    final r = await _dio.get('/profile/$publicId');
    return r.data as Map<String, dynamic>;
  }
}
