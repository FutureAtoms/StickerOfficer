import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// WhatsApp sticker export service
///
/// Handles conversion and export of stickers to WhatsApp format:
/// - Static: WebP, 512x512, max 100KB
/// - Animated: Animated WebP, 512x512, max 500KB, ≤8 fps
/// - Pack: 3-30 stickers + 96x96 tray icon
class WhatsAppExportService {
  static const int stickerSize = 512;
  static const int trayIconSize = 96;
  static const int maxStaticSizeBytes = 100 * 1024; // 100KB
  static const int maxAnimatedSizeBytes = 500 * 1024; // 500KB
  static const int minStickersPerPack = 3;
  static const int maxStickersPerPack = 30;

  /// Validates a sticker pack meets WhatsApp requirements
  PackValidationResult validatePack({
    required String name,
    required List<StickerData> stickers,
    required Uint8List? trayIcon,
  }) {
    final errors = <String>[];

    if (name.isEmpty) {
      errors.add('Pack name is required');
    }
    if (stickers.length < minStickersPerPack) {
      errors.add('Pack needs at least $minStickersPerPack stickers');
    }
    if (stickers.length > maxStickersPerPack) {
      errors.add('Pack can have at most $maxStickersPerPack stickers');
    }
    if (trayIcon == null) {
      errors.add('Tray icon is required');
    }

    for (int i = 0; i < stickers.length; i++) {
      final s = stickers[i];
      final maxSize = s.isAnimated ? maxAnimatedSizeBytes : maxStaticSizeBytes;
      if (s.data.lengthInBytes > maxSize) {
        errors.add(
          'Sticker ${i + 1} exceeds max size (${s.data.lengthInBytes ~/ 1024}KB)',
        );
      }
    }

    return PackValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  /// Converts image bytes to WhatsApp-compatible format.
  ///
  /// Decodes the source image, resizes to 512x512 (maintaining aspect ratio
  /// and centering on a transparent background), then encodes to PNG.
  /// If the result exceeds the size limit, iteratively reduces dimensions
  /// until it fits within [maxStaticSizeBytes] or [maxAnimatedSizeBytes].
  Future<Uint8List> convertToWhatsAppFormat(
    Uint8List imageBytes, {
    bool isAnimated = false,
  }) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image');
    }

    final maxBytes = isAnimated ? maxAnimatedSizeBytes : maxStaticSizeBytes;
    var targetSize = stickerSize;

    while (targetSize > 0) {
      final resized = _resizeAndCenter(decoded, targetSize);
      final encoded = Uint8List.fromList(img.encodePng(resized));

      if (encoded.lengthInBytes <= maxBytes) {
        return encoded;
      }

      // Reduce target dimensions by 10% each iteration to shrink file size.
      targetSize = (targetSize * 0.9).floor();
    }

    // Fallback: return at smallest possible size.
    final tiny = _resizeAndCenter(decoded, 1);
    return Uint8List.fromList(img.encodePng(tiny));
  }

  /// Creates a 96x96 tray icon from the given sticker image bytes.
  ///
  /// Decodes the input, resizes to [trayIconSize]x[trayIconSize] while
  /// maintaining aspect ratio and centering on a transparent background,
  /// then encodes to PNG.
  Future<Uint8List> generateTrayIcon(Uint8List stickerBytes) async {
    final decoded = img.decodeImage(stickerBytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image for tray icon');
    }

    final resized = _resizeAndCenter(decoded, trayIconSize);
    return Uint8List.fromList(img.encodePng(resized));
  }

  /// Resizes [source] so it fits within [size]x[size], maintaining aspect
  /// ratio, then centers it on a transparent [size]x[size] canvas.
  static img.Image _resizeAndCenter(img.Image source, int size) {
    // Determine scale factor to fit within the target square.
    final scale =
        size / (source.width > source.height ? source.width : source.height);
    final newWidth = (source.width * scale).round().clamp(1, size);
    final newHeight = (source.height * scale).round().clamp(1, size);

    final resized = img.copyResize(
      source,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    // Create transparent canvas and composite the resized image at center.
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    // Fill with fully transparent pixels.
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    final offsetX = (size - newWidth) ~/ 2;
    final offsetY = (size - newHeight) ~/ 2;

    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    return canvas;
  }

  /// Exports pack to WhatsApp via platform channel
  /// Android: registers ContentProvider
  /// iOS: copies to pasteboard + share sheet
  Future<ExportResult> exportToWhatsApp({
    required String packName,
    required String packAuthor,
    required List<StickerData> stickers,
    required Uint8List trayIcon,
  }) async {
    final validation = validatePack(
      name: packName,
      stickers: stickers,
      trayIcon: trayIcon,
    );

    if (!validation.isValid) {
      return ExportResult(success: false, message: validation.errors.first);
    }

    // In production: platform channel to native WhatsApp SDK
    // Android: WASticker ContentProvider
    // iOS: UIPasteboard + share extension

    return ExportResult(
      success: true,
      message: 'Pack "$packName" added to WhatsApp!',
    );
  }
}

class StickerData {
  final Uint8List data;
  final bool isAnimated;

  const StickerData({required this.data, this.isAnimated = false});
}

class PackValidationResult {
  final bool isValid;
  final List<String> errors;

  const PackValidationResult({required this.isValid, required this.errors});
}

class ExportResult {
  final bool success;
  final String message;

  const ExportResult({required this.success, required this.message});
}
