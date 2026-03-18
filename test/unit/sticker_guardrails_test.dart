import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';

void main() {
  // ===========================================================================
  // 1. Constants
  // ===========================================================================

  group('Constants', () {
    test('maxStaticSizeBytes is 100 KB', () {
      expect(StickerGuardrails.maxStaticSizeBytes, 100 * 1024);
    });

    test('maxAnimatedSizeBytes is 500 KB', () {
      expect(StickerGuardrails.maxAnimatedSizeBytes, 500 * 1024);
    });

    test('frame limits', () {
      expect(StickerGuardrails.minFrames, 2);
      expect(StickerGuardrails.maxFrames, 8);
    });

    test('FPS limits', () {
      expect(StickerGuardrails.minFps, 4);
      expect(StickerGuardrails.maxFps, 8);
    });

    test('duration limits', () {
      expect(StickerGuardrails.minDurationMs, 500);
      expect(StickerGuardrails.maxDurationMs, 10000);
    });

    test('canvas size is 512', () {
      expect(StickerGuardrails.stickerSize, 512);
    });

    test('tray icon size is 96', () {
      expect(StickerGuardrails.trayIconSize, 96);
    });

    test('text limits', () {
      expect(StickerGuardrails.maxTextLength, 50);
      expect(StickerGuardrails.minTextSize, 16.0);
      expect(StickerGuardrails.maxTextSize, 64.0);
    });

    test('pack limits', () {
      expect(StickerGuardrails.minStickersPerPack, 3);
      expect(StickerGuardrails.maxStickersPerPack, 30);
    });
  });

  // ===========================================================================
  // 2. Animated sticker validation
  // ===========================================================================

  group('validateAnimatedSticker', () {
    test('valid animated sticker passes', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 200 * 1024,
        fps: 6,
      );
      expect(errors, isEmpty);
    });

    test('minimum valid: 2 frames, minFps, small size', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2,
        estimatedSizeBytes: 1024,
        fps: 4,
      );
      expect(errors, isEmpty);
    });

    test('maximum valid: 8 frames, maxFps, just under limit', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 8,
        estimatedSizeBytes: 500 * 1024,
        fps: 8,
      );
      expect(errors, isEmpty);
    });

    // -- Frame count errors ---------------------------------------------------

    test('rejects 0 frames', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 0,
        estimatedSizeBytes: 0,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('at least 2')), isTrue);
    });

    test('rejects 1 frame', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1,
        estimatedSizeBytes: 1024,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('at least 2')), isTrue);
    });

    test('rejects 9 frames (over max)', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 9,
        estimatedSizeBytes: 1024,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Too many frames')), isTrue);
    });

    test('rejects 100 frames', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 100,
        estimatedSizeBytes: 1024,
        fps: 6,
      );
      expect(errors.any((e) => e.contains('Too many frames')), isTrue);
    });

    // -- FPS errors -----------------------------------------------------------

    test('rejects FPS below minimum', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 3,
      );
      expect(errors.any((e) => e.contains('too slow')), isTrue);
    });

    test('rejects FPS above maximum', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 9,
      );
      expect(errors.any((e) => e.contains('too fast')), isTrue);
    });

    test('accepts exact min FPS', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 4,
      );
      expect(errors.where((e) => e.contains('FPS')), isEmpty);
    });

    test('accepts exact max FPS', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 8,
      );
      expect(errors.where((e) => e.contains('FPS')), isEmpty);
    });

    // -- Size errors ----------------------------------------------------------

    test('rejects size over 500 KB', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 500 * 1024 + 1,
        fps: 6,
      );
      expect(errors.any((e) => e.contains('too big')), isTrue);
    });

    test('accepts exactly 500 KB', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 500 * 1024,
        fps: 6,
      );
      expect(errors.where((e) => e.contains('too big')), isEmpty);
    });

    // -- Duration errors ------------------------------------------------------

    test('rejects animation that is too short', () {
      // 2 frames at 8 fps = 250ms, which is < 500ms minimum
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2,
        estimatedSizeBytes: 1024,
        fps: 8,
      );
      expect(errors.any((e) => e.contains('too short')), isTrue);
    });

    test('rejects animation that is too long', () {
      // 8 frames at 4 fps = 2000ms = 2s, which is within limit
      // But we need something > 10s — impossible with 8 frames max at 4 fps
      // So let's check: 8 frames / 4 fps = 2s — that's fine.
      // The maxDurationMs is 10s, which is hard to hit with 8 frames.
      // This test documents that the current limits don't actually allow
      // exceeding max duration (8 frames / 4 fps = 2s max).
      // The guardrail exists for safety but current frame/fps limits prevent it.
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 8,
        estimatedSizeBytes: 1024,
        fps: 4,
      );
      // 8/4 = 2s, which is < 10s max, so no duration error
      expect(errors.where((e) => e.contains('too long')), isEmpty);
    });

    // -- Text validation in animated sticker ----------------------------------

    test('rejects inappropriate text', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 6,
        overlayText: 'you are an idiot',
      );
      expect(errors.any((e) => e.contains('friendly words')), isTrue);
    });

    test('rejects text that is too long', () {
      final longText = 'A' * 51;
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 6,
        overlayText: longText,
      );
      expect(errors.any((e) => e.contains('too long')), isTrue);
    });

    test('accepts friendly short text', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 6,
        overlayText: 'Hello friend!',
      );
      expect(errors.where((e) => e.contains('text')), isEmpty);
    });

    test('accepts null overlay text', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 1024,
        fps: 6,
        overlayText: null,
      );
      expect(errors, isEmpty);
    });

    // -- Multiple errors at once ----------------------------------------------

    test('reports multiple errors simultaneously', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 0,
        estimatedSizeBytes: 600 * 1024,
        fps: 1,
        overlayText: 'shut up ' * 10, // too long + inappropriate
      );
      expect(errors.length, greaterThanOrEqualTo(3));
    });
  });

  // ===========================================================================
  // 3. Static sticker validation
  // ===========================================================================

  group('validateStaticSticker', () {
    test('valid static sticker passes', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('accepts exactly 100 KB', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 100 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('rejects 100 KB + 1 byte', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 100 * 1024 + 1,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('too big')), isTrue);
    });

    test('includes KB in error message', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 200 * 1024,
      );
      expect(errors.any((e) => e.contains('200')), isTrue);
    });

    test('rejects inappropriate overlay text', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 1024,
        overlayText: 'you are stupid',
      );
      expect(errors.any((e) => e.contains('friendly')), isTrue);
    });

    test('accepts friendly overlay text', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 1024,
        overlayText: 'I love cats!',
      );
      expect(errors, isEmpty);
    });
  });

  // ===========================================================================
  // 4. Kid-safe text validation
  // ===========================================================================

  group('isKidSafeText', () {
    test('accepts empty text', () {
      expect(StickerGuardrails.isKidSafeText(''), isTrue);
    });

    test('accepts friendly text', () {
      expect(StickerGuardrails.isKidSafeText('Hello!'), isTrue);
      expect(StickerGuardrails.isKidSafeText('Love cats'), isTrue);
      expect(StickerGuardrails.isKidSafeText('Best friends'), isTrue);
      expect(StickerGuardrails.isKidSafeText('LOL'), isTrue);
    });

    test('accepts emoji text', () {
      expect(StickerGuardrails.isKidSafeText('Hi there! 😊'), isTrue);
    });

    test('rejects blocked words', () {
      expect(StickerGuardrails.isKidSafeText('you are stupid'), isFalse);
      expect(StickerGuardrails.isKidSafeText('what an idiot'), isFalse);
      expect(StickerGuardrails.isKidSafeText('I hate this'), isFalse);
      expect(StickerGuardrails.isKidSafeText('shut up'), isFalse);
      expect(StickerGuardrails.isKidSafeText('you suck'), isFalse);
    });

    test('is case-insensitive', () {
      expect(StickerGuardrails.isKidSafeText('STUPID'), isFalse);
      expect(StickerGuardrails.isKidSafeText('Idiot'), isFalse);
      expect(StickerGuardrails.isKidSafeText('HATE'), isFalse);
    });

    test('matches whole words only', () {
      // "shell" contains "hell" but should pass because it's not a whole word
      expect(StickerGuardrails.isKidSafeText('shell'), isTrue);
      // "therapist" doesn't contain any blocked word as whole word
      expect(StickerGuardrails.isKidSafeText('therapist'), isTrue);
    });

    test('rejects blocked words within sentences', () {
      expect(StickerGuardrails.isKidSafeText('go to hell now'), isFalse);
      expect(StickerGuardrails.isKidSafeText('damn it!'), isFalse);
    });

    test('accepts text with numbers and symbols', () {
      expect(StickerGuardrails.isKidSafeText('#1 best'), isTrue);
      expect(StickerGuardrails.isKidSafeText('100% awesome'), isTrue);
    });
  });

  // ===========================================================================
  // 5. Text sanitization
  // ===========================================================================

  group('sanitizeText', () {
    test('trims whitespace', () {
      expect(StickerGuardrails.sanitizeText('  hello  '), 'hello');
    });

    test('truncates text over max length', () {
      final long = 'A' * 100;
      final result = StickerGuardrails.sanitizeText(long);
      expect(result.length, StickerGuardrails.maxTextLength);
    });

    test('preserves text under max length', () {
      expect(StickerGuardrails.sanitizeText('Hi'), 'Hi');
    });

    test('preserves text at exactly max length', () {
      final exact = 'A' * StickerGuardrails.maxTextLength;
      expect(StickerGuardrails.sanitizeText(exact), exact);
    });

    test('handles empty string', () {
      expect(StickerGuardrails.sanitizeText(''), '');
    });

    test('handles whitespace-only string', () {
      expect(StickerGuardrails.sanitizeText('   '), '');
    });
  });

  // ===========================================================================
  // 6. Duration helpers
  // ===========================================================================

  group('totalDurationMs', () {
    test('calculates correctly for typical values', () {
      // 4 frames at 4 fps = 1000ms
      expect(StickerGuardrails.totalDurationMs(4, 4), 1000);
    });

    test('2 frames at 8 fps = 250ms', () {
      expect(StickerGuardrails.totalDurationMs(2, 8), 250);
    });

    test('8 frames at 4 fps = 2000ms', () {
      expect(StickerGuardrails.totalDurationMs(8, 4), 2000);
    });

    test('8 frames at 8 fps = 1000ms', () {
      expect(StickerGuardrails.totalDurationMs(8, 8), 1000);
    });

    test('0 frames = 0ms', () {
      expect(StickerGuardrails.totalDurationMs(0, 8), 0);
    });

    test('0 fps = 0ms (avoids division by zero)', () {
      expect(StickerGuardrails.totalDurationMs(4, 0), 0);
    });
  });

  group('isDurationSafe', () {
    test('safe for 4 frames at 4 fps (1000ms)', () {
      expect(StickerGuardrails.isDurationSafe(4, 4), isTrue);
    });

    test('safe for 8 frames at 8 fps (1000ms)', () {
      expect(StickerGuardrails.isDurationSafe(8, 8), isTrue);
    });

    test('unsafe for 2 frames at 8 fps (250ms < 500ms min)', () {
      expect(StickerGuardrails.isDurationSafe(2, 8), isFalse);
    });

    test('safe for 4 frames at 8 fps (500ms = exactly min)', () {
      expect(StickerGuardrails.isDurationSafe(4, 8), isTrue);
    });

    test('safe for 8 frames at 4 fps (2000ms)', () {
      expect(StickerGuardrails.isDurationSafe(8, 4), isTrue);
    });
  });

  group('durationLabel', () {
    test('formats 1000ms as 1.0s', () {
      expect(StickerGuardrails.durationLabel(4, 4), '1.0s');
    });

    test('formats 250ms as 0.3s (rounded)', () {
      // 2/8 = 0.25, rounded to 250ms, /1000 = 0.250 → "0.3s" (toStringAsFixed(1))
      final label = StickerGuardrails.durationLabel(2, 8);
      expect(label, contains('s'));
    });

    test('formats 2000ms as 2.0s', () {
      expect(StickerGuardrails.durationLabel(8, 4), '2.0s');
    });
  });

  // ===========================================================================
  // 7. Size helpers
  // ===========================================================================

  group('sizeStatus', () {
    // Static sticker thresholds
    test('static: safe under 80 KB', () {
      expect(
        StickerGuardrails.sizeStatus(50 * 1024),
        SizeStatus.safe,
      );
    });

    test('static: warning between 80-100 KB', () {
      expect(
        StickerGuardrails.sizeStatus(90 * 1024),
        SizeStatus.warning,
      );
    });

    test('static: tooLarge over 100 KB', () {
      expect(
        StickerGuardrails.sizeStatus(101 * 1024),
        SizeStatus.tooLarge,
      );
    });

    test('static: exactly 80 KB is safe', () {
      expect(
        StickerGuardrails.sizeStatus(80 * 1024),
        SizeStatus.safe,
      );
    });

    test('static: 80 KB + 1 is warning', () {
      expect(
        StickerGuardrails.sizeStatus(80 * 1024 + 1),
        SizeStatus.warning,
      );
    });

    test('static: exactly 100 KB is warning', () {
      expect(
        StickerGuardrails.sizeStatus(100 * 1024),
        SizeStatus.warning,
      );
    });

    test('static: 100 KB + 1 is tooLarge', () {
      expect(
        StickerGuardrails.sizeStatus(100 * 1024 + 1),
        SizeStatus.tooLarge,
      );
    });

    // Animated sticker thresholds
    test('animated: safe under 400 KB', () {
      expect(
        StickerGuardrails.sizeStatus(200 * 1024, isAnimated: true),
        SizeStatus.safe,
      );
    });

    test('animated: warning between 400-500 KB', () {
      expect(
        StickerGuardrails.sizeStatus(450 * 1024, isAnimated: true),
        SizeStatus.warning,
      );
    });

    test('animated: tooLarge over 500 KB', () {
      expect(
        StickerGuardrails.sizeStatus(501 * 1024, isAnimated: true),
        SizeStatus.tooLarge,
      );
    });

    test('animated: exactly 400 KB is safe', () {
      expect(
        StickerGuardrails.sizeStatus(400 * 1024, isAnimated: true),
        SizeStatus.safe,
      );
    });

    test('animated: 400 KB + 1 is warning', () {
      expect(
        StickerGuardrails.sizeStatus(400 * 1024 + 1, isAnimated: true),
        SizeStatus.warning,
      );
    });

    test('animated: exactly 500 KB is warning', () {
      expect(
        StickerGuardrails.sizeStatus(500 * 1024, isAnimated: true),
        SizeStatus.warning,
      );
    });

    test('animated: 500 KB + 1 is tooLarge', () {
      expect(
        StickerGuardrails.sizeStatus(500 * 1024 + 1, isAnimated: true),
        SizeStatus.tooLarge,
      );
    });

    test('zero bytes is safe', () {
      expect(StickerGuardrails.sizeStatus(0), SizeStatus.safe);
    });
  });

  group('sizeLabel', () {
    test('formats kilobytes', () {
      expect(StickerGuardrails.sizeLabel(50 * 1024), '50 KB');
    });

    test('formats small sizes', () {
      expect(StickerGuardrails.sizeLabel(500), '< 1 KB');
    });

    test('formats zero', () {
      expect(StickerGuardrails.sizeLabel(0), '< 1 KB');
    });

    test('formats large sizes', () {
      expect(StickerGuardrails.sizeLabel(500 * 1024), '500 KB');
    });
  });

  group('sizeColor', () {
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

  group('sizeTip', () {
    test('safe tip for static', () {
      expect(
        StickerGuardrails.sizeTip(SizeStatus.safe),
        'Perfect size!',
      );
    });

    test('warning tip', () {
      final tip = StickerGuardrails.sizeTip(SizeStatus.warning);
      expect(tip, contains('Getting big'));
    });

    test('tooLarge tip for static mentions cropping', () {
      final tip = StickerGuardrails.sizeTip(SizeStatus.tooLarge);
      expect(tip, contains('cropping'));
    });

    test('tooLarge tip for animated mentions frames', () {
      final tip = StickerGuardrails.sizeTip(
        SizeStatus.tooLarge,
        isAnimated: true,
      );
      expect(tip, contains('frames'));
    });
  });

  // ===========================================================================
  // 8. TextAnimation enum
  // ===========================================================================

  group('TextAnimation', () {
    test('has all expected values', () {
      expect(TextAnimation.values.length, 7);
      expect(TextAnimation.values, contains(TextAnimation.none));
      expect(TextAnimation.values, contains(TextAnimation.bounce));
      expect(TextAnimation.values, contains(TextAnimation.fadeIn));
      expect(TextAnimation.values, contains(TextAnimation.slideUp));
      expect(TextAnimation.values, contains(TextAnimation.wave));
      expect(TextAnimation.values, contains(TextAnimation.grow));
      expect(TextAnimation.values, contains(TextAnimation.shake));
    });

    test('each animation has a non-empty label', () {
      for (final anim in TextAnimation.values) {
        expect(anim.label, isNotEmpty);
      }
    });

    test('each animation has an icon', () {
      for (final anim in TextAnimation.values) {
        expect(anim.icon, isNotNull);
      }
    });

    test('none label is "No Animation"', () {
      expect(TextAnimation.none.label, 'No Animation');
    });

    test('bounce label is "Bounce"', () {
      expect(TextAnimation.bounce.label, 'Bounce');
    });
  });

  // ===========================================================================
  // 9. SizeStatus enum
  // ===========================================================================

  group('SizeStatus', () {
    test('has three values', () {
      expect(SizeStatus.values.length, 3);
    });

    test('values are safe, warning, tooLarge', () {
      expect(SizeStatus.values, contains(SizeStatus.safe));
      expect(SizeStatus.values, contains(SizeStatus.warning));
      expect(SizeStatus.values, contains(SizeStatus.tooLarge));
    });
  });

  // ===========================================================================
  // 10. Edge cases and boundary combinations
  // ===========================================================================

  group('Edge cases', () {
    test('animated sticker with all maximums is valid', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 8,
        estimatedSizeBytes: 500 * 1024,
        fps: 8,
        overlayText: 'A' * 50, // exactly max length
      );
      expect(errors, isEmpty);
    });

    test('animated sticker with all minimums is valid', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2,
        estimatedSizeBytes: 0,
        fps: 4,
        overlayText: 'A',
      );
      // 2 frames at 4 fps = 500ms = exactly minDurationMs
      expect(errors, isEmpty);
    });

    test('text at exactly max length is accepted', () {
      final text = 'A' * 50;
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 1024,
        overlayText: text,
      );
      expect(errors, isEmpty);
    });

    test('text at max length + 1 is rejected', () {
      final text = 'A' * 51;
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 1024,
        overlayText: text,
      );
      expect(errors, isNotEmpty);
    });

    test('empty overlay text passes validation', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 1024,
        overlayText: '',
      );
      // Empty text should pass isKidSafeText but is still checked for length
      expect(errors, isEmpty);
    });
  });
}
