import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel for native WhatsApp sticker integration.
///
/// On Android, this uses a ContentProvider + Intent to add stickers
/// directly to WhatsApp's sticker tray (not just share as images).
class WhatsAppStickerChannel {
  static const _channel = MethodChannel(
    'com.futureatoms.sticker_officer/whatsapp',
  );

  /// Adds a sticker pack to WhatsApp using the native Android intent.
  ///
  /// [identifier] Unique pack ID (used by ContentProvider)
  /// [name] Display name of the pack
  /// [publisher] Author/publisher name
  /// [stickerPaths] List of sticker image file paths (PNG or WebP)
  /// [trayIconPath] Path to the tray icon image
  /// [animatedStickerPack] Whether the entire pack contains animated stickers
  ///
  /// The native side prepares the ContentProvider directory structure WhatsApp
  /// expects and marks the pack metadata as static or animated.
  static Future<WhatsAppResult> addStickerPack({
    required String identifier,
    required String name,
    required String publisher,
    required List<String> stickerPaths,
    required String trayIconPath,
    bool animatedStickerPack = false,
  }) async {
    if (!Platform.isAndroid) {
      return const WhatsAppResult(
        success: false,
        message:
            'WhatsApp sticker packs are only supported on Android. '
            'On iOS, stickers will be shared as images.',
      );
    }

    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('addStickerPackToWhatsApp', {
            'identifier': identifier,
            'name': name,
            'publisher': publisher,
            'stickerPaths': stickerPaths,
            'trayIconPath': trayIconPath,
            'animatedStickerPack': animatedStickerPack,
          });

      if (result == null) {
        return const WhatsAppResult(
          success: false,
          message: 'No response from native platform',
        );
      }

      return WhatsAppResult(
        success: result['success'] as bool? ?? false,
        message: result['message'] as String? ?? 'Unknown result',
      );
    } on PlatformException catch (e) {
      debugPrint('WhatsApp sticker channel error: ${e.message}');
      return WhatsAppResult(
        success: false,
        message: e.message ?? 'Failed to add sticker pack',
      );
    }
  }

  /// Checks if WhatsApp is installed on the device.
  static Future<bool> isWhatsAppInstalled() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isWhatsAppInstalled');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Encodes a still image file into a static WebP file on Android.
  static Future<bool> encodeStaticWebpFrame({
    required String inputPath,
    required String outputPath,
    int quality = 80,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'encodeStaticWebpFrame',
        {'inputPath': inputPath, 'outputPath': outputPath, 'quality': quality},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Static WebP frame encode error: ${e.message}');
      return false;
    }
  }
}

class WhatsAppResult {
  final bool success;
  final String message;

  const WhatsAppResult({required this.success, required this.message});
}
