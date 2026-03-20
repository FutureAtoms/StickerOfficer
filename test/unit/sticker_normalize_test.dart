import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';

void main() {
  group('normalizeStaticSticker', () {
    test('JPEG input produces 512x512 PNG', () {
      final source = img.Image(width: 200, height: 150, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(128, 200, 50));
      final jpegBytes = Uint8List.fromList(img.encodeJpg(source));

      final result = StickerGuardrails.normalizeStaticSticker(jpegBytes);

      final decoded = img.decodePng(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('small PNG input is resized to 512x512', () {
      final source = img.Image(width: 64, height: 64, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 128));
      final pngBytes = Uint8List.fromList(img.encodePng(source));

      final result = StickerGuardrails.normalizeStaticSticker(pngBytes);

      final decoded = img.decodePng(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('already 512x512 small PNG passes through as PNG', () {
      final source = img.Image(width: 512, height: 512, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));
      final pngBytes = Uint8List.fromList(img.encodePng(source));

      final result = StickerGuardrails.normalizeStaticSticker(pngBytes);

      final decoded = img.decodePng(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('large photographic input returns valid 512x512 PNG', () {
      // Create a complex image that won't compress easily
      final source = img.Image(width: 1024, height: 768, numChannels: 3);
      // Fill with varied colors to make it harder to compress
      for (int y = 0; y < source.height; y++) {
        for (int x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
        }
      }
      final jpegBytes = Uint8List.fromList(img.encodeJpg(source, quality: 100));

      final result = StickerGuardrails.normalizeStaticSticker(jpegBytes);

      // Should still be a valid 512x512 PNG (may be > 100KB, that's OK)
      final decoded = img.decodePng(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('output is always PNG format', () {
      final source = img.Image(width: 300, height: 300, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(0, 100, 200));
      final jpegBytes = Uint8List.fromList(img.encodeJpg(source));

      final result = StickerGuardrails.normalizeStaticSticker(jpegBytes);

      // PNG magic bytes: 0x89 0x50 0x4E 0x47
      expect(result[0], 0x89);
      expect(result[1], 0x50); // 'P'
      expect(result[2], 0x4E); // 'N'
      expect(result[3], 0x47); // 'G'
    });

    test('non-square image is centered on transparent canvas', () {
      final source = img.Image(width: 200, height: 100, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));
      final pngBytes = Uint8List.fromList(img.encodePng(source));

      final result = StickerGuardrails.normalizeStaticSticker(pngBytes);
      final decoded = img.decodePng(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);

      // Top-left corner should be transparent (padding area)
      final topLeft = decoded.getPixel(0, 0);
      expect(topLeft.a.toInt(), 0);
    });
  });
}
