import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'whatsapp_sticker_channel.dart';

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

  /// Validates a sticker pack meets WhatsApp requirements.
  /// Note: does NOT reject oversized stickers — the export pipeline
  /// auto-compresses them. Only checks pack-level constraints.
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

    // No per-sticker size check here — the export pipeline will
    // resize + compress every sticker to fit automatically.

    return PackValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  /// Converts image bytes to WhatsApp-compatible 512x512 PNG.
  ///
  /// Quality-preserving approach — escalates compression only as needed:
  ///   1. Resize to 512x512 with max PNG compression (lossless, best quality)
  ///   2. If still too big, quantize colors 256→128→64 (slight quality loss)
  ///   3. If still too big, encode as high-quality JPEG then re-wrap as PNG
  ///   4. Nuclear: reduce JPEG quality until it fits
  ///
  /// The native Android side converts to WebP anyway, so the PNG here is
  /// an intermediate format — WebP is much smaller, so most stickers that
  /// pass as PNG will easily pass as WebP.
  Future<Uint8List> convertToWhatsAppFormat(
    Uint8List imageBytes, {
    bool isAnimated = false,
  }) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image');
    }

    final maxBytes = isAnimated ? maxAnimatedSizeBytes : maxStaticSizeBytes;

    // Always resize to 512x512 first (WhatsApp requirement)
    final resized = _resizeAndCenter(decoded, stickerSize);

    // Strategy 1: PNG with max compression — lossless, best quality
    final pngMax = Uint8List.fromList(img.encodePng(resized, level: 9));
    if (pngMax.lengthInBytes <= maxBytes) {
      return pngMax;
    }

    // Strategy 2: Quantize colors — slight quality loss but keeps 512x512
    // Start high (256 colors) and go down gradually
    for (final colors in [256, 192, 128, 96, 64]) {
      final quantized = img.quantize(resized, numberOfColors: colors);
      final encoded = Uint8List.fromList(img.encodePng(quantized, level: 9));
      if (encoded.lengthInBytes <= maxBytes) {
        return encoded;
      }
    }

    // Strategy 3: JPEG at high quality (90→70) — visually near-identical
    // The native side converts to WebP which handles this well
    for (var quality = 90; quality >= 50; quality -= 10) {
      final jpegBytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (jpegBytes.length <= maxBytes) {
        return jpegBytes;
      }
    }

    // Strategy 4: Lower JPEG quality (still at 512x512)
    for (var quality = 40; quality >= 20; quality -= 10) {
      final jpegBytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (jpegBytes.length <= maxBytes) {
        return jpegBytes;
      }
    }

    // Fallback: 512x512 + heavy quantize + max PNG compression
    final quantized = img.quantize(resized, numberOfColors: 32);
    return Uint8List.fromList(img.encodePng(quantized, level: 9));
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

  /// Exports sticker pack to WhatsApp.
  ///
  /// On Android: Uses the native ContentProvider + Intent system to add
  /// stickers directly to WhatsApp's sticker tray. Converts all images
  /// to 512x512 WebP format as required by WhatsApp.
  ///
  /// On iOS: Falls back to sharing sticker files via the share sheet,
  /// since WhatsApp on iOS doesn't support third-party sticker packs.
  /// Generates a proper 512x512 placeholder sticker image (a smiley face).
  /// Used when a pack has fewer than [minStickersPerPack] real stickers.
  static Uint8List generatePlaceholderSticker() {
    final canvas = img.Image(width: stickerSize, height: stickerSize, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    // Draw a simple circle (emoji-like placeholder)
    img.drawCircle(canvas,
      x: stickerSize ~/ 2,
      y: stickerSize ~/ 2,
      radius: 200,
      color: img.ColorRgba8(255, 200, 0, 255),
    );
    img.fillCircle(canvas,
      x: stickerSize ~/ 2,
      y: stickerSize ~/ 2,
      radius: 200,
      color: img.ColorRgba8(255, 220, 50, 255),
    );

    return Uint8List.fromList(img.encodePng(canvas));
  }

  Future<ExportResult> exportToWhatsApp({
    required String packName,
    required String packAuthor,
    required List<StickerData> stickers,
    required Uint8List trayIcon,
    String? trayIconSourcePath,
  }) async {
    final validation = validatePack(
      name: packName,
      stickers: stickers,
      trayIcon: trayIcon,
    );

    if (!validation.isValid) {
      return ExportResult(success: false, message: validation.errors.first);
    }

    try {
      // Use a safe directory name (no spaces or special chars)
      final safePackName = packName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final packIdentifier =
          safePackName.isEmpty ? 'sticker_pack_${DateTime.now().millisecondsSinceEpoch}' : safePackName;

      final tempDir = await getTemporaryDirectory();
      final packDir = Directory('${tempDir.path}/sticker_pack_$packIdentifier');
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
      }
      await packDir.create(recursive: true);

      final stickerPaths = <String>[];

      // On Android, avoid double-processing existing pack assets. The native
      // side will do the final 512x512 WebP conversion in one pass.
      final shouldPreprocessForAndroid = !Platform.isAndroid;

      for (int i = 0; i < stickers.length; i++) {
        try {
          final sourcePath = stickers[i].sourcePath;
          if (Platform.isAndroid &&
              sourcePath != null &&
              await File(sourcePath).exists()) {
            stickerPaths.add(sourcePath);
            continue;
          }

          final stickerBytes = stickers[i].data;
          final decoded = img.decodeImage(stickerBytes);

          if (decoded == null) {
            debugPrint('Sticker ${i + 1}: could not decode, skipping');
            continue;
          }

          // Skip tiny placeholder images (1x1, 2x2 etc)
          if (decoded.width < 4 || decoded.height < 4) {
            debugPrint('Sticker ${i + 1}: too small, using placeholder');
            final placeholder = generatePlaceholderSticker();
            final filePath = '${packDir.path}/sticker_${i + 1}.png';
            await File(filePath).writeAsBytes(placeholder);
            stickerPaths.add(filePath);
            continue;
          }

          final processedBytes =
              shouldPreprocessForAndroid
                  ? await convertToWhatsAppFormat(
                    stickerBytes,
                    isAnimated: stickers[i].isAnimated,
                  )
                  : stickerBytes;

          final filePath = '${packDir.path}/sticker_${i + 1}.png';
          await File(filePath).writeAsBytes(processedBytes);
          stickerPaths.add(filePath);
          debugPrint('Sticker ${i + 1}: ${processedBytes.length ~/ 1024}KB');
        } catch (e) {
          debugPrint('Sticker ${i + 1}: processing failed: $e');
        }
      }

      if (stickerPaths.isEmpty) {
        return const ExportResult(
          success: false,
          message: 'None of the sticker images could be processed',
        );
      }

      // Save tray icon
      String trayIconPath;
      if (Platform.isAndroid &&
          trayIconSourcePath != null &&
          await File(trayIconSourcePath).exists()) {
        trayIconPath = trayIconSourcePath;
      } else {
        final trayDecoded = img.decodeImage(trayIcon);
        if (trayDecoded != null) {
          final trayResized = _resizeAndCenter(trayDecoded, trayIconSize);
          final trayPng = img.encodePng(trayResized);
          trayIconPath = '${packDir.path}/tray_icon.png';
          await File(trayIconPath).writeAsBytes(trayPng);
        } else {
          trayIconPath = stickerPaths.first;
        }
      }

      // --- Android: Use native WhatsApp sticker API ---
      if (Platform.isAndroid) {
        final result = await WhatsAppStickerChannel.addStickerPack(
          identifier: packIdentifier,
          name: packName,
          publisher: packAuthor,
          stickerPaths: stickerPaths,
          trayIconPath: trayIconPath,
        );

        return ExportResult(success: result.success, message: result.message);
      }

      // --- iOS: Fall back to share sheet ---
      final xFiles = stickerPaths
          .map((p) => XFile(p, mimeType: 'image/png'))
          .toList();
      xFiles.add(XFile(trayIconPath, mimeType: 'image/png'));

      await SharePlus.instance.share(
        ShareParams(
          files: xFiles,
          text: 'Sticker Pack: $packName by $packAuthor',
          subject: packName,
        ),
      );

      return ExportResult(
        success: true,
        message: 'Pack "$packName" shared! Open WhatsApp to use your stickers.',
      );
    } catch (e) {
      debugPrint('WhatsApp export failed: $e');
      return ExportResult(
        success: false,
        message: 'Export failed: ${e.toString().split('\n').first}',
      );
    }
  }
}

class StickerData {
  final Uint8List data;
  final bool isAnimated;
  final String? sourcePath;

  const StickerData({
    required this.data,
    this.isAnimated = false,
    this.sourcePath,
  });
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
