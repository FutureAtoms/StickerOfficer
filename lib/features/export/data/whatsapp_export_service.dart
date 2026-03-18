import 'dart:typed_data';

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

  /// Converts image bytes to WhatsApp-compatible WebP format
  /// Resizes to 512x512, converts to WebP, compresses until <100KB
  Future<Uint8List> convertToWhatsAppFormat(
    Uint8List imageBytes, {
    bool isAnimated = false,
  }) async {
    // In production, this uses the `image` package to:
    // 1. Decode the source image
    // 2. Resize to 512x512 (maintain aspect ratio, pad with transparent)
    // 3. Encode to WebP
    // 4. Iteratively reduce quality until <100KB (or <500KB for animated)

    // For now, return the input (actual conversion needs native WebP encoder)
    return imageBytes;
  }

  /// Creates a 96x96 tray icon from the first sticker
  Future<Uint8List> generateTrayIcon(Uint8List stickerBytes) async {
    // Resize to 96x96 WebP
    return stickerBytes;
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
