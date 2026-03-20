import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Thin wrapper around [ImagePicker] for testability.
///
/// Override via Riverpod in tests to return mock picks.
class ImagePickerService {
  final ImagePicker _picker;

  ImagePickerService([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  /// Pick multiple images from the gallery.
  Future<List<XFile>> pickMultiImage() => _picker.pickMultiImage();
}

final imagePickerServiceProvider = Provider<ImagePickerService>(
  (ref) => ImagePickerService(),
);
