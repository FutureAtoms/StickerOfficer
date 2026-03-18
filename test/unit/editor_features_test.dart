import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/features/export/data/whatsapp_export_service.dart';

/// Tests for image cropping, text addition, text animation, GIF/animated
/// sticker generation, and size/duration guardrails.
///
/// Widget tests (requiring real widgets & platform channels) are minimal here.
/// This file focuses on the *logic* that drives those features — validation,
/// size estimation, image conversion — which can run in a pure Dart test env.
void main() {
  // ===========================================================================
  // 1. Image Cropping — conversion to WhatsApp format
  // ===========================================================================

  group('Image cropping — WhatsApp format conversion', () {
    late WhatsAppExportService service;

    setUp(() {
      service = WhatsAppExportService();
    });

    test('landscape image is resized and centered to 512x512', () async {
      // Create a 1000x500 landscape image
      final landscape = img.Image(width: 1000, height: 500);
      img.fill(landscape, color: img.ColorRgba8(200, 100, 50, 255));
      final input = Uint8List.fromList(img.encodePng(landscape));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('portrait image is resized and centered to 512x512', () async {
      final portrait = img.Image(width: 300, height: 900);
      img.fill(portrait, color: img.ColorRgba8(50, 200, 100, 255));
      final input = Uint8List.fromList(img.encodePng(portrait));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('square image is resized to 512x512', () async {
      final square = img.Image(width: 256, height: 256);
      img.fill(square, color: img.ColorRgba8(100, 100, 255, 255));
      final input = Uint8List.fromList(img.encodePng(square));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('tiny image (1x1) is upscaled to 512x512', () async {
      final tiny = img.Image(width: 1, height: 1);
      img.fill(tiny, color: img.ColorRgba8(255, 0, 0, 255));
      final input = Uint8List.fromList(img.encodePng(tiny));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('oversized image produces output within 100 KB', () async {
      // Create a large noisy image that compresses poorly
      final large = img.Image(width: 2000, height: 2000);
      // Fill with varied colors to make PNG larger
      for (var y = 0; y < 2000; y++) {
        for (var x = 0; x < 2000; x++) {
          large.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
        }
      }
      final input = Uint8List.fromList(img.encodePng(large));

      final output = await service.convertToWhatsAppFormat(input);

      expect(
        output.lengthInBytes,
        lessThanOrEqualTo(WhatsAppExportService.maxStaticSizeBytes),
      );
    });

    test('rejects invalid image data', () {
      final garbage = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      expect(
        () => service.convertToWhatsAppFormat(garbage),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ===========================================================================
  // 2. Text addition — validation and sanitization
  // ===========================================================================

  group('Text addition — validation', () {
    test('short friendly text passes all checks', () {
      const text = 'Hello World!';
      expect(StickerGuardrails.isKidSafeText(text), isTrue);
      expect(text.length, lessThanOrEqualTo(StickerGuardrails.maxTextLength));
    });

    test('text with emojis is accepted', () {
      const text = 'Cool beans! 🫘✨';
      expect(StickerGuardrails.isKidSafeText(text), isTrue);
    });

    test('sanitizeText truncates and trims', () {
      final messy = '   ${'Z' * 100}   ';
      final clean = StickerGuardrails.sanitizeText(messy);
      expect(clean.length, StickerGuardrails.maxTextLength);
      expect(clean, startsWith('Z'));
    });

    test('text size range matches guardrails', () {
      expect(StickerGuardrails.minTextSize, 16.0);
      expect(StickerGuardrails.maxTextSize, 64.0);
      // Slider should go from 16 to 64
      expect(StickerGuardrails.maxTextSize - StickerGuardrails.minTextSize, 48.0);
    });

    test('kid-safe filter blocks "loser"', () {
      expect(StickerGuardrails.isKidSafeText('you are a loser'), isFalse);
    });

    test('kid-safe filter blocks "ugly"', () {
      expect(StickerGuardrails.isKidSafeText('so ugly'), isFalse);
    });

    test('kid-safe filter allows "shell" (contains "hell" but not whole word)', () {
      expect(StickerGuardrails.isKidSafeText('a seashell'), isTrue);
    });

    test('kid-safe filter allows "assessment" (contains "ass" but not whole word)', () {
      // Depending on the blocklist, "assessment" should pass because "ass" isn't
      // in the current blocked list — just documenting the behavior
      expect(StickerGuardrails.isKidSafeText('assessment'), isTrue);
    });
  });

  // ===========================================================================
  // 3. Text animation — configuration
  // ===========================================================================

  group('Text animation configuration', () {
    test('TextAnimation has 7 presets', () {
      expect(TextAnimation.values.length, 7);
    });

    test('default animation is none', () {
      // "none" should always be the first value for default selection
      expect(TextAnimation.values.first, TextAnimation.none);
    });

    test('all animations have distinct labels', () {
      final labels = TextAnimation.values.map((a) => a.label).toSet();
      expect(labels.length, TextAnimation.values.length);
    });

    test('bounce animation label', () {
      expect(TextAnimation.bounce.label, 'Bounce');
    });

    test('fadeIn animation label', () {
      expect(TextAnimation.fadeIn.label, 'Fade In');
    });

    test('slideUp animation label', () {
      expect(TextAnimation.slideUp.label, 'Slide Up');
    });

    test('wave animation label', () {
      expect(TextAnimation.wave.label, 'Wave');
    });

    test('grow animation label', () {
      expect(TextAnimation.grow.label, 'Grow');
    });

    test('shake animation label', () {
      expect(TextAnimation.shake.label, 'Shake');
    });
  });

  // ===========================================================================
  // 4. GIF / Animated sticker generation
  // ===========================================================================

  group('GIF / animated sticker generation', () {
    test('creates a valid GIF from multiple frames', () {
      final frame1 = img.Image(width: 512, height: 512);
      img.fill(frame1, color: img.ColorRgba8(255, 0, 0, 255));
      frame1.frameDuration = 13; // ~130ms per frame

      final frame2 = img.Image(width: 512, height: 512);
      img.fill(frame2, color: img.ColorRgba8(0, 255, 0, 255));
      frame2.frameDuration = 13;

      final frame3 = img.Image(width: 512, height: 512);
      img.fill(frame3, color: img.ColorRgba8(0, 0, 255, 255));
      frame3.frameDuration = 13;

      // Build animation
      final animation = frame1.clone();
      animation.addFrame(frame2);
      animation.addFrame(frame3);

      final gifBytes = img.encodeGif(animation);

      // Verify it's a valid GIF
      expect(gifBytes, isNotEmpty);
      expect(gifBytes[0], 0x47); // 'G'
      expect(gifBytes[1], 0x49); // 'I'
      expect(gifBytes[2], 0x46); // 'F'
    });

    test('GIF frame duration is set correctly for 8 fps', () {
      // 8 fps = 125ms per frame = 12.5 centiseconds ≈ 13 (rounded)
      const frameDurationMs = 125;
      final centiseconds = (frameDurationMs / 10).round();
      expect(centiseconds, 13); // 12.5 rounds to 13
    });

    test('GIF frame duration is set correctly for 4 fps', () {
      // 4 fps = 250ms per frame = 25 centiseconds
      const frameDurationMs = 250;
      final centiseconds = (frameDurationMs / 10).round();
      expect(centiseconds, 25);
    });

    test('GIF frame duration is set correctly for 6 fps', () {
      // 6 fps ≈ 167ms per frame ≈ 17 centiseconds
      const frameDurationMs = 167;
      final centiseconds = (frameDurationMs / 10).round();
      expect(centiseconds, 17);
    });

    test('resizing to 512x512 maintains expected dimensions', () {
      final original = img.Image(width: 800, height: 400);
      img.fill(original, color: img.ColorRgba8(128, 128, 128, 255));

      final resized = img.copyResize(
        original,
        width: 512,
        height: 512,
        interpolation: img.Interpolation.linear,
      );

      expect(resized.width, 512);
      expect(resized.height, 512);
    });

    test('GIF with text overlay can be created', () {
      final frame = img.Image(width: 512, height: 512);
      img.fill(frame, color: img.ColorRgba8(255, 200, 150, 255));

      // Add text to frame (simulates text overlay)
      img.drawString(
        frame,
        'Hello!',
        font: img.arial24,
        x: 200,
        y: 440,
        color: img.ColorRgba8(255, 255, 255, 230),
      );

      frame.frameDuration = 13;

      final frame2 = frame.clone();
      frame2.frameDuration = 13;

      final animation = frame.clone();
      animation.addFrame(frame2);

      final gifBytes = img.encodeGif(animation);
      expect(gifBytes, isNotEmpty);
      expect(gifBytes.length, greaterThan(0));
    });

    test('GIF from imported GIF - decode and re-encode', () {
      // Create a simple GIF
      final frame1 = img.Image(width: 64, height: 64);
      img.fill(frame1, color: img.ColorRgba8(255, 0, 0, 255));
      frame1.frameDuration = 10;

      final frame2 = img.Image(width: 64, height: 64);
      img.fill(frame2, color: img.ColorRgba8(0, 255, 0, 255));
      frame2.frameDuration = 10;

      final original = frame1.clone();
      original.addFrame(frame2);

      final originalBytes = img.encodeGif(original);

      // Decode it back (simulates GIF import)
      final decoded = img.decodeGif(Uint8List.fromList(originalBytes));
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 2);

      // Extract frames
      final extractedFrame0 = decoded.getFrame(0);
      final extractedFrame1 = decoded.getFrame(1);

      expect(extractedFrame0.width, 64);
      expect(extractedFrame1.width, 64);

      // Resize frames to sticker size
      final resized0 = img.copyResize(extractedFrame0, width: 512, height: 512);
      final resized1 = img.copyResize(extractedFrame1, width: 512, height: 512);

      resized0.frameDuration = 13;
      resized1.frameDuration = 13;

      // Re-encode
      final reAnimation = resized0.clone();
      reAnimation.addFrame(resized1);
      final reEncoded = img.encodeGif(reAnimation);

      expect(reEncoded, isNotEmpty);
    });

    test('GIF size estimation heuristic', () {
      // The animated sticker screen uses: rawSum * 0.6
      final frameBytes = <Uint8List>[
        Uint8List(50 * 1024), // 50 KB
        Uint8List(50 * 1024), // 50 KB
        Uint8List(50 * 1024), // 50 KB
      ];

      final rawSum = frameBytes.fold<int>(0, (s, b) => s + b.length);
      final estimate = (rawSum * 0.6).round();

      // 150 KB * 0.6 = 90 KB
      expect(estimate, 90 * 1024); // 92160 bytes
      expect(
        StickerGuardrails.sizeStatus(estimate, isAnimated: true),
        SizeStatus.safe,
      );
    });
  });

  // ===========================================================================
  // 5. Size guardrails
  // ===========================================================================

  group('Size guardrails', () {
    test('static sticker at 50 KB is safe', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('static sticker at 100 KB boundary is valid', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 100 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('static sticker at 100 KB + 1 is invalid', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 100 * 1024 + 1,
      );
      expect(errors, isNotEmpty);
    });

    test('animated sticker at 300 KB is safe', () {
      final status = StickerGuardrails.sizeStatus(
        300 * 1024,
        isAnimated: true,
      );
      expect(status, SizeStatus.safe);
    });

    test('animated sticker at 450 KB is warning', () {
      final status = StickerGuardrails.sizeStatus(
        450 * 1024,
        isAnimated: true,
      );
      expect(status, SizeStatus.warning);
    });

    test('animated sticker at 501 KB is too large', () {
      final status = StickerGuardrails.sizeStatus(
        501 * 1024,
        isAnimated: true,
      );
      expect(status, SizeStatus.tooLarge);
    });
  });

  // ===========================================================================
  // 6. Duration guardrails
  // ===========================================================================

  group('Duration guardrails', () {
    test('2 frames at 4 fps = 500ms (minimum safe duration)', () {
      final duration = StickerGuardrails.totalDurationMs(2, 4);
      expect(duration, 500);
      expect(StickerGuardrails.isDurationSafe(2, 4), isTrue);
    });

    test('2 frames at 8 fps = 250ms (too short)', () {
      final duration = StickerGuardrails.totalDurationMs(2, 8);
      expect(duration, 250);
      expect(StickerGuardrails.isDurationSafe(2, 8), isFalse);
    });

    test('3 frames at 8 fps = 375ms (too short)', () {
      final duration = StickerGuardrails.totalDurationMs(3, 8);
      expect(duration, 375);
      expect(StickerGuardrails.isDurationSafe(3, 8), isFalse);
    });

    test('4 frames at 8 fps = 500ms (exactly minimum)', () {
      final duration = StickerGuardrails.totalDurationMs(4, 8);
      expect(duration, 500);
      expect(StickerGuardrails.isDurationSafe(4, 8), isTrue);
    });

    test('8 frames at 4 fps = 2000ms (well within limits)', () {
      final duration = StickerGuardrails.totalDurationMs(8, 4);
      expect(duration, 2000);
      expect(StickerGuardrails.isDurationSafe(8, 4), isTrue);
    });

    test('max possible duration: 8 frames at 4 fps = 2s (safe)', () {
      // With current limits (max 8 frames, min 4 fps), max duration is 2s
      // This is well under the 10s limit
      final maxDuration = StickerGuardrails.totalDurationMs(8, 4);
      expect(maxDuration, lessThanOrEqualTo(StickerGuardrails.maxDurationMs));
    });

    test('duration label formats correctly', () {
      expect(StickerGuardrails.durationLabel(4, 4), '1.0s');
      expect(StickerGuardrails.durationLabel(8, 4), '2.0s');
      expect(StickerGuardrails.durationLabel(8, 8), '1.0s');
    });
  });

  // ===========================================================================
  // 7. Tray icon generation
  // ===========================================================================

  group('Tray icon generation', () {
    late WhatsAppExportService service;

    setUp(() {
      service = WhatsAppExportService();
    });

    test('generates 96x96 tray icon from 512x512 sticker', () async {
      final sticker = img.Image(width: 512, height: 512);
      img.fill(sticker, color: img.ColorRgba8(255, 128, 0, 255));
      final input = Uint8List.fromList(img.encodePng(sticker));

      final output = await service.generateTrayIcon(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 96);
      expect(decoded.height, 96);
    });

    test('generates 96x96 tray icon from non-square image', () async {
      final sticker = img.Image(width: 800, height: 400);
      img.fill(sticker, color: img.ColorRgba8(0, 128, 255, 255));
      final input = Uint8List.fromList(img.encodePng(sticker));

      final output = await service.generateTrayIcon(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 96);
      expect(decoded.height, 96);
    });
  });

  // ===========================================================================
  // 8. Pack validation integration
  // ===========================================================================

  group('Pack validation integration', () {
    late WhatsAppExportService service;

    setUp(() {
      service = WhatsAppExportService();
    });

    test('minimal valid pack: 3 stickers at safe size', () {
      final result = service.validatePack(
        name: 'My Pack',
        stickers: List.generate(
          3,
          (_) => StickerData(data: Uint8List(50 * 1024)),
        ),
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isTrue);
    });

    test('maximal valid pack: 30 stickers at max size', () {
      final result = service.validatePack(
        name: 'Big Pack',
        stickers: List.generate(
          30,
          (_) => StickerData(data: Uint8List(100 * 1024)),
        ),
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isTrue);
    });

    test('mixed static and animated stickers in one pack', () {
      final stickers = [
        StickerData(data: Uint8List(80 * 1024), isAnimated: false),
        StickerData(data: Uint8List(400 * 1024), isAnimated: true),
        StickerData(data: Uint8List(50 * 1024), isAnimated: false),
      ];

      final result = service.validatePack(
        name: 'Mixed Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isTrue);
    });

    test('rejects pack with no name', () {
      final result = service.validatePack(
        name: '',
        stickers: List.generate(
          3,
          (_) => StickerData(data: Uint8List(1024)),
        ),
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Pack name is required'));
    });

    test('rejects pack with too few stickers', () {
      final result = service.validatePack(
        name: 'Small',
        stickers: [StickerData(data: Uint8List(1024))],
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isFalse);
    });
  });

  // ===========================================================================
  // 9. Kid-friendly UX validation
  // ===========================================================================

  group('Kid-friendly UX', () {
    test('error messages use friendly language', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 0,
        estimatedSizeBytes: 0,
        fps: 6,
      );
      // Should say "Add at least" not "Error: insufficient frames"
      expect(errors.first, contains('Add at least'));
    });

    test('size tip uses encouraging language', () {
      expect(
        StickerGuardrails.sizeTip(SizeStatus.safe),
        'Perfect size!',
      );
    });

    test('warning tip gives helpful advice', () {
      final tip = StickerGuardrails.sizeTip(SizeStatus.warning);
      expect(tip, contains('simpler'));
    });

    test('too-large tip for animated gives actionable advice', () {
      final tip = StickerGuardrails.sizeTip(SizeStatus.tooLarge, isAnimated: true);
      expect(tip, contains('Remove'));
    });

    test('kid-safe filter rejects "kill"', () {
      expect(StickerGuardrails.isKidSafeText('kill'), isFalse);
    });

    test('kid-safe filter rejects "die"', () {
      expect(StickerGuardrails.isKidSafeText('die'), isFalse);
    });

    test('kid-safe filter allows "diet"', () {
      // "diet" contains "die" but should pass word-boundary check
      expect(StickerGuardrails.isKidSafeText('diet'), isTrue);
    });

    test('kid-safe filter allows "paradise"', () {
      // "paradise" contains "die" but not as a whole word
      expect(StickerGuardrails.isKidSafeText('paradise'), isTrue);
    });

    test('kid-safe filter allows "skilled"', () {
      // "skilled" contains "kill" but not as a whole word
      expect(StickerGuardrails.isKidSafeText('skilled'), isTrue);
    });
  });
}
