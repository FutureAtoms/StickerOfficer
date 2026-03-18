import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';

/// Comprehensive guardrail tests covering size, duration, FPS, kid-safe text,
/// and all edge cases needed to ensure the app is safe and easy for kids.
void main() {
  // ===========================================================================
  // 1. Animated sticker size guardrails
  // ===========================================================================

  group('Animated Sticker Size Guardrails', () {
    test('safe when under 400KB', () {
      final status = StickerGuardrails.sizeStatus(300 * 1024, isAnimated: true);
      expect(status, SizeStatus.safe);
    });

    test('warning between 400-500KB', () {
      final status = StickerGuardrails.sizeStatus(450 * 1024, isAnimated: true);
      expect(status, SizeStatus.warning);
    });

    test('tooLarge above 500KB', () {
      final status = StickerGuardrails.sizeStatus(501 * 1024, isAnimated: true);
      expect(status, SizeStatus.tooLarge);
    });

    test('exact 500KB boundary is warning (above 400KB threshold)', () {
      final status = StickerGuardrails.sizeStatus(500 * 1024, isAnimated: true);
      expect(status, SizeStatus.warning);
    });

    test('exact 400KB boundary is safe', () {
      final status = StickerGuardrails.sizeStatus(400 * 1024, isAnimated: true);
      expect(status, SizeStatus.safe);
    });

    test('401KB is warning', () {
      final status =
          StickerGuardrails.sizeStatus(400 * 1024 + 1, isAnimated: true);
      expect(status, SizeStatus.warning);
    });
  });

  // ===========================================================================
  // 2. Static sticker size guardrails
  // ===========================================================================

  group('Static Sticker Size Guardrails', () {
    test('safe when under 80KB', () {
      final status =
          StickerGuardrails.sizeStatus(50 * 1024, isAnimated: false);
      expect(status, SizeStatus.safe);
    });

    test('warning between 80-100KB', () {
      final status =
          StickerGuardrails.sizeStatus(90 * 1024, isAnimated: false);
      expect(status, SizeStatus.warning);
    });

    test('tooLarge above 100KB', () {
      final status =
          StickerGuardrails.sizeStatus(101 * 1024, isAnimated: false);
      expect(status, SizeStatus.tooLarge);
    });
  });

  // ===========================================================================
  // 3. Size colors (kid-friendly indicators)
  // ===========================================================================

  group('Size Colors', () {
    test('safe is green', () {
      expect(StickerGuardrails.sizeColor(SizeStatus.safe), Colors.green);
    });

    test('warning is orange', () {
      expect(StickerGuardrails.sizeColor(SizeStatus.warning), Colors.orange);
    });

    test('tooLarge is red', () {
      expect(StickerGuardrails.sizeColor(SizeStatus.tooLarge), Colors.red);
    });
  });

  // ===========================================================================
  // 4. Size tips (kid-friendly messages)
  // ===========================================================================

  group('Size Tips', () {
    test('safe tip is "Perfect size!"', () {
      expect(
        StickerGuardrails.sizeTip(SizeStatus.safe),
        'Perfect size!',
      );
    });

    test('warning tip mentions simpler images', () {
      expect(
        StickerGuardrails.sizeTip(SizeStatus.warning),
        contains('Getting big'),
      );
    });

    test('tooLarge animated tip mentions frames', () {
      expect(
        StickerGuardrails.sizeTip(SizeStatus.tooLarge, isAnimated: true),
        contains('frames'),
      );
    });

    test('tooLarge static tip mentions cropping', () {
      expect(
        StickerGuardrails.sizeTip(SizeStatus.tooLarge, isAnimated: false),
        contains('cropping'),
      );
    });
  });

  // ===========================================================================
  // 5. Size label formatting
  // ===========================================================================

  group('Size Labels', () {
    test('formats 0 bytes as "< 1 KB"', () {
      expect(StickerGuardrails.sizeLabel(0), '< 1 KB');
    });

    test('formats 100 bytes as "< 1 KB"', () {
      expect(StickerGuardrails.sizeLabel(100), '< 1 KB');
    });

    test('formats 1024 bytes as "1 KB"', () {
      expect(StickerGuardrails.sizeLabel(1024), '1 KB');
    });

    test('formats 500KB correctly', () {
      expect(StickerGuardrails.sizeLabel(500 * 1024), '500 KB');
    });

    test('formats 1023 bytes as "< 1 KB"', () {
      expect(StickerGuardrails.sizeLabel(1023), '< 1 KB');
    });
  });

  // ===========================================================================
  // 6. Duration guardrails
  // ===========================================================================

  group('Duration Guardrails', () {
    test('2 frames at 4 FPS = 500ms (safe, min boundary)', () {
      final ms = StickerGuardrails.totalDurationMs(2, 4);
      expect(ms, 500);
      expect(StickerGuardrails.isDurationSafe(2, 4), isTrue);
    });

    test('8 frames at 4 FPS = 2000ms (safe)', () {
      final ms = StickerGuardrails.totalDurationMs(8, 4);
      expect(ms, 2000);
      expect(StickerGuardrails.isDurationSafe(8, 4), isTrue);
    });

    test('8 frames at 8 FPS = 1000ms (safe)', () {
      final ms = StickerGuardrails.totalDurationMs(8, 8);
      expect(ms, 1000);
      expect(StickerGuardrails.isDurationSafe(8, 8), isTrue);
    });

    test('2 frames at 8 FPS = 250ms (too short)', () {
      final ms = StickerGuardrails.totalDurationMs(2, 8);
      expect(ms, 250);
      expect(StickerGuardrails.isDurationSafe(2, 8), isFalse);
    });

    test('0 FPS returns 0ms', () {
      expect(StickerGuardrails.totalDurationMs(8, 0), 0);
    });

    test('duration label format is "X.Xs"', () {
      final label = StickerGuardrails.durationLabel(4, 8);
      expect(label, '0.5s');
    });

    test('duration label for 2 frames at 4 FPS', () {
      expect(StickerGuardrails.durationLabel(2, 4), '0.5s');
    });
  });

  // ===========================================================================
  // 7. Frame count validation
  // ===========================================================================

  group('Frame Count Validation', () {
    test('0 frames fails validation', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 0,
        estimatedSizeBytes: 1000,
        fps: 8,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('Add at least'));
    });

    test('1 frame fails validation', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1,
        estimatedSizeBytes: 1000,
        fps: 8,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('Add at least 2'));
    });

    test('2 frames passes frame count check', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2,
        estimatedSizeBytes: 1000,
        fps: 4, // 2 frames / 4 FPS = 500ms = min boundary
      );
      // No frame count error (might have duration issues)
      expect(errors.any((e) => e.contains('Add at least')), isFalse);
    });

    test('8 frames passes (max boundary)', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 8,
        estimatedSizeBytes: 1000,
        fps: 8,
      );
      expect(errors.any((e) => e.contains('Too many')), isFalse);
    });

    test('9 frames fails validation', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 9,
        estimatedSizeBytes: 1000,
        fps: 8,
      );
      expect(errors.any((e) => e.contains('Too many frames')), isTrue);
    });
  });

  // ===========================================================================
  // 8. FPS validation
  // ===========================================================================

  group('FPS Validation', () {
    test('3 FPS is too slow', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1000,
        fps: 3,
      );
      expect(errors.any((e) => e.contains('too slow')), isTrue);
    });

    test('4 FPS is valid (min boundary)', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1000,
        fps: 4,
      );
      expect(errors.any((e) => e.contains('slow')), isFalse);
    });

    test('8 FPS is valid (max boundary)', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1000,
        fps: 8,
      );
      expect(errors.any((e) => e.contains('fast')), isFalse);
    });

    test('9 FPS is too fast', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1000,
        fps: 9,
      );
      expect(errors.any((e) => e.contains('too fast')), isTrue);
    });
  });

  // ===========================================================================
  // 9. Text validation (kid-safe)
  // ===========================================================================

  group('Kid-Safe Text Validation', () {
    test('empty text is safe', () {
      expect(StickerGuardrails.isKidSafeText(''), isTrue);
    });

    test('whitespace only is safe', () {
      expect(StickerGuardrails.isKidSafeText('   '), isTrue);
    });

    test('"hello" is safe', () {
      expect(StickerGuardrails.isKidSafeText('hello'), isTrue);
    });

    test('"I love stickers" is safe', () {
      expect(StickerGuardrails.isKidSafeText('I love stickers'), isTrue);
    });

    test('"damn" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('damn'), isFalse);
    });

    test('"hell" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('hell'), isFalse);
    });

    test('"stupid" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('stupid'), isFalse);
    });

    test('"idiot" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('idiot'), isFalse);
    });

    test('"hate" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('hate'), isFalse);
    });

    test('"kill" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('kill'), isFalse);
    });

    test('"die" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('die'), isFalse);
    });

    test('"ugly" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('ugly'), isFalse);
    });

    test('"shut up" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('shut up'), isFalse);
    });

    test('"loser" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('loser'), isFalse);
    });

    test('case insensitive — "STUPID" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('STUPID'), isFalse);
    });

    test('case insensitive — "HaTe" is blocked', () {
      expect(StickerGuardrails.isKidSafeText('HaTe'), isFalse);
    });

    test('blocked word in sentence is caught', () {
      expect(StickerGuardrails.isKidSafeText('you are stupid'), isFalse);
    });

    test('partial word match does not block (e.g., "shell" contains "hell")',
        () {
      // "hell" is a whole word match, "shell" should pass since
      // the regex uses word boundaries
      expect(StickerGuardrails.isKidSafeText('shell'), isTrue);
    });

    test('"hello" is safe despite containing "hell"', () {
      expect(StickerGuardrails.isKidSafeText('hello'), isTrue);
    });

    test('emojis are safe', () {
      expect(StickerGuardrails.isKidSafeText('\u{1F600}\u{1F60E}'), isTrue);
    });

    test('mixed emoji and text is safe', () {
      expect(StickerGuardrails.isKidSafeText('Fun time! \u{1F389}'), isTrue);
    });

    test('numbers are safe', () {
      expect(StickerGuardrails.isKidSafeText('12345'), isTrue);
    });
  });

  // ===========================================================================
  // 10. Text sanitization
  // ===========================================================================

  group('Text Sanitization', () {
    test('trims whitespace', () {
      expect(StickerGuardrails.sanitizeText('  hello  '), 'hello');
    });

    test('truncates text beyond max length', () {
      final longText = 'a' * 100;
      final result = StickerGuardrails.sanitizeText(longText);
      expect(result.length, StickerGuardrails.maxTextLength);
    });

    test('preserves text within limit', () {
      expect(StickerGuardrails.sanitizeText('hello'), 'hello');
    });

    test('empty string stays empty', () {
      expect(StickerGuardrails.sanitizeText(''), '');
    });

    test('max length is 50 characters', () {
      expect(StickerGuardrails.maxTextLength, 50);
    });
  });

  // ===========================================================================
  // 11. TextAnimation enum
  // ===========================================================================

  group('TextAnimation Enum', () {
    test('has exactly 7 values', () {
      expect(TextAnimation.values.length, 7);
    });

    test('none label is "No Animation"', () {
      expect(TextAnimation.none.label, 'No Animation');
    });

    test('bounce label is "Bounce"', () {
      expect(TextAnimation.bounce.label, 'Bounce');
    });

    test('fadeIn label is "Fade In"', () {
      expect(TextAnimation.fadeIn.label, 'Fade In');
    });

    test('slideUp label is "Slide Up"', () {
      expect(TextAnimation.slideUp.label, 'Slide Up');
    });

    test('wave label is "Wave"', () {
      expect(TextAnimation.wave.label, 'Wave');
    });

    test('grow label is "Grow"', () {
      expect(TextAnimation.grow.label, 'Grow');
    });

    test('shake label is "Shake"', () {
      expect(TextAnimation.shake.label, 'Shake');
    });

    test('each animation has a unique icon', () {
      final icons = TextAnimation.values.map((a) => a.icon).toSet();
      expect(icons.length, 7);
    });
  });

  // ===========================================================================
  // 12. Constants verification
  // ===========================================================================

  group('Constants', () {
    test('stickerSize is 512', () {
      expect(StickerGuardrails.stickerSize, 512);
    });

    test('trayIconSize is 96', () {
      expect(StickerGuardrails.trayIconSize, 96);
    });

    test('maxStaticSizeBytes is 100KB', () {
      expect(StickerGuardrails.maxStaticSizeBytes, 100 * 1024);
    });

    test('maxAnimatedSizeBytes is 500KB', () {
      expect(StickerGuardrails.maxAnimatedSizeBytes, 500 * 1024);
    });

    test('minFrames is 2', () {
      expect(StickerGuardrails.minFrames, 2);
    });

    test('maxFrames is 8', () {
      expect(StickerGuardrails.maxFrames, 8);
    });

    test('minFps is 4', () {
      expect(StickerGuardrails.minFps, 4);
    });

    test('maxFps is 8', () {
      expect(StickerGuardrails.maxFps, 8);
    });

    test('minDurationMs is 500', () {
      expect(StickerGuardrails.minDurationMs, 500);
    });

    test('maxDurationMs is 10000', () {
      expect(StickerGuardrails.maxDurationMs, 10000);
    });

    test('maxTextLength is 50', () {
      expect(StickerGuardrails.maxTextLength, 50);
    });

    test('minTextSize is 16', () {
      expect(StickerGuardrails.minTextSize, 16.0);
    });

    test('maxTextSize is 64', () {
      expect(StickerGuardrails.maxTextSize, 64.0);
    });

    test('minStickersPerPack is 3', () {
      expect(StickerGuardrails.minStickersPerPack, 3);
    });

    test('maxStickersPerPack is 30', () {
      expect(StickerGuardrails.maxStickersPerPack, 30);
    });
  });

  // ===========================================================================
  // 13. Static sticker validation
  // ===========================================================================

  group('Static Sticker Validation', () {
    test('50KB is valid', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('100KB is valid (boundary)', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 100 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('101KB is invalid', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 101 * 1024,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('too big'));
    });

    test('with safe text is valid', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
        overlayText: 'Hello!',
      );
      expect(errors, isEmpty);
    });

    test('with unsafe text fails', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
        overlayText: 'you are stupid',
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('friendly')), isTrue);
    });

    test('with too-long text fails', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
        overlayText: 'a' * 100,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('too long')), isTrue);
    });
  });

  // ===========================================================================
  // 14. Animated sticker validation — combined checks
  // ===========================================================================

  group('Animated Sticker Combined Validation', () {
    test('valid 4 frames, 200KB, 6 FPS passes', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 200 * 1024,
        fps: 6,
      );
      expect(errors, isEmpty);
    });

    test('valid with safe overlay text', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 200 * 1024,
        fps: 6,
        overlayText: 'Fun!',
      );
      expect(errors, isEmpty);
    });

    test('multiple errors when all invalid', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1,
        estimatedSizeBytes: 600 * 1024,
        fps: 3,
        overlayText: 'stupid',
      );
      // frame count, fps, size, text = multiple errors
      expect(errors.length, greaterThanOrEqualTo(3));
    });

    test('error messages are kid-friendly (no technical jargon)', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 0,
        estimatedSizeBytes: 0,
        fps: 8,
      );
      for (final error in errors) {
        expect(error.contains('exception'), isFalse);
        expect(error.contains('null'), isFalse);
        expect(error.contains('index'), isFalse);
      }
    });
  });
}
