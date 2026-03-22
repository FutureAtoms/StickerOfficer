import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'huggingface_api.dart';

/// Provides a singleton [HuggingFaceApiService] instance.
/// AI generation is proxied through the Cloudflare Worker which
/// handles API key management and rate limiting.
final huggingFaceApiProvider = Provider<HuggingFaceApiService>((ref) {
  return HuggingFaceApiService();
});

/// Holds the list of generated sticker images (raw bytes).
final generatedStickersProvider = StateProvider<List<Uint8List>>((ref) => []);
