import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'huggingface_api.dart';

// API key loaded from --dart-define=HF_API_KEY=xxx at build time.
// Run: flutter run --dart-define=HF_API_KEY=your_key_here
const kHuggingFaceApiKey = String.fromEnvironment('HF_API_KEY');

/// Provides a singleton [HuggingFaceApiService] instance.
final huggingFaceApiProvider = Provider<HuggingFaceApiService>((ref) {
  return HuggingFaceApiService();
});

/// Holds the list of generated sticker images (raw bytes).
final generatedStickersProvider = StateProvider<List<Uint8List>>((ref) => []);
