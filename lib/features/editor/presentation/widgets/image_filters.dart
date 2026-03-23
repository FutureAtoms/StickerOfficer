import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Available sticker filters.
enum StickerFilter {
  none('Original'),
  grayscale('B&W'),
  sepia('Sepia'),
  invert('Invert'),
  vintage('Vintage'),
  cool('Cool'),
  warm('Warm');

  final String label;
  const StickerFilter(this.label);
}

/// Applies a filter to an image. Runs synchronously — call via compute() for
/// large images.
img.Image applyFilter(img.Image source, StickerFilter filter) {
  switch (filter) {
    case StickerFilter.none:
      return source;
    case StickerFilter.grayscale:
      return img.grayscale(source);
    case StickerFilter.sepia:
      return _applySepia(source);
    case StickerFilter.invert:
      return img.invert(source);
    case StickerFilter.vintage:
      return _applyVintage(source);
    case StickerFilter.cool:
      return _applyColorShift(source, redShift: -10, greenShift: 0, blueShift: 20);
    case StickerFilter.warm:
      return _applyColorShift(source, redShift: 20, greenShift: 10, blueShift: -15);
  }
}

img.Image _applySepia(img.Image source) {
  final result = source.clone();
  for (final pixel in result) {
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final gray = (0.299 * r + 0.587 * g + 0.114 * b).round();
    pixel.r = (gray + 40).clamp(0, 255);
    pixel.g = (gray + 20).clamp(0, 255);
    pixel.b = gray.clamp(0, 255);
  }
  return result;
}

img.Image _applyVintage(img.Image source) {
  final result = source.clone();
  for (final pixel in result) {
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final gray = (0.299 * r + 0.587 * g + 0.114 * b).round();
    // Warm sepia with slight fade
    pixel.r = (gray + 25).clamp(0, 255);
    pixel.g = (gray + 10).clamp(0, 255);
    pixel.b = (gray - 15).clamp(0, 255);
    // Reduce contrast slightly
    pixel.r = (pixel.r.toInt() * 0.9 + 25).round().clamp(0, 255);
    pixel.g = (pixel.g.toInt() * 0.9 + 20).round().clamp(0, 255);
    pixel.b = (pixel.b.toInt() * 0.9 + 15).round().clamp(0, 255);
  }
  return result;
}

img.Image _applyColorShift(img.Image source, {
  required int redShift,
  required int greenShift,
  required int blueShift,
}) {
  final result = source.clone();
  for (final pixel in result) {
    pixel.r = (pixel.r.toInt() + redShift).clamp(0, 255);
    pixel.g = (pixel.g.toInt() + greenShift).clamp(0, 255);
    pixel.b = (pixel.b.toInt() + blueShift).clamp(0, 255);
  }
  return result;
}

/// Parameters for running filter in an isolate via compute().
class FilterParams {
  final Uint8List pngBytes;
  final StickerFilter filter;
  const FilterParams({required this.pngBytes, required this.filter});
}

/// Top-level function for compute() isolate.
Uint8List applyFilterIsolate(FilterParams params) {
  final source = img.decodePng(params.pngBytes);
  if (source == null) return params.pngBytes;
  final filtered = applyFilter(source, params.filter);
  return Uint8List.fromList(img.encodePng(filtered));
}
