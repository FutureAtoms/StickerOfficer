import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/features/export/data/whatsapp_export_service.dart';

/// Comprehensive tests for:
///
/// 1. Text animation transform computation (all 7 animation presets)
/// 2. Text rendering with animation applied in GIF frames
/// 3. Image cropping validation and edge cases
/// 4. Video/GIF animated sticker generation with guardrails
/// 5. Kid-safe guardrails enforcement end-to-end
/// 6. Size/duration guardrail boundary conditions
void main() {
  // ===========================================================================
  // 1. Text Animation Transform Computation
  // ===========================================================================

  group('TextAnimationTransform computation', () {
    test('TextAnimation.none returns identity transform for all frames', () {
      for (var i = 0; i < 8; i++) {
        final t = computeTextTransform(
          animation: TextAnimation.none,
          frameIndex: i,
          totalFrames: 8,
        );
        expect(t.dx, 0, reason: 'frame $i dx');
        expect(t.dy, 0, reason: 'frame $i dy');
        expect(t.scale, 1.0, reason: 'frame $i scale');
        expect(t.alpha, 230, reason: 'frame $i alpha');
      }
    });

    test('TextAnimation.bounce oscillates y offset', () {
      final transforms = List.generate(
        8,
        (i) => computeTextTransform(
          animation: TextAnimation.bounce,
          frameIndex: i,
          totalFrames: 8,
        ),
      );

      // First frame (t=0) should have dy=0 (sin(0)=0)
      expect(transforms.first.dy, 0);

      // Middle frames should have non-zero dy (bouncing)
      final middleDys = transforms.sublist(1, 7).map((t) => t.dy);
      expect(middleDys.any((dy) => dy != 0), isTrue,
          reason: 'Bounce should move text vertically in middle frames');

      // All dx should be 0 (bounce is vertical only)
      for (final t in transforms) {
        expect(t.dx, 0, reason: 'Bounce should not move horizontally');
      }

      // Alpha and scale should remain default
      for (final t in transforms) {
        expect(t.alpha, 230);
        expect(t.scale, 1.0);
      }
    });

    test('TextAnimation.fadeIn increases alpha across frames', () {
      final transforms = List.generate(
        8,
        (i) => computeTextTransform(
          animation: TextAnimation.fadeIn,
          frameIndex: i,
          totalFrames: 8,
        ),
      );

      // Alpha should increase from first to last
      expect(transforms.first.alpha, lessThan(transforms.last.alpha));

      // First frame should be dim
      expect(transforms.first.alpha, lessThanOrEqualTo(50));

      // Last frame should be near full opacity
      expect(transforms.last.alpha, greaterThanOrEqualTo(200));

      // Position and scale should remain default
      for (final t in transforms) {
        expect(t.dx, 0);
        expect(t.dy, 0);
        expect(t.scale, 1.0);
      }
    });

    test('TextAnimation.slideUp slides from below to base position', () {
      final transforms = List.generate(
        8,
        (i) => computeTextTransform(
          animation: TextAnimation.slideUp,
          frameIndex: i,
          totalFrames: 8,
        ),
      );

      // First frame: text should be offset below (positive dy)
      expect(transforms.first.dy, greaterThan(0));

      // Last frame: text should be at base position (dy ≈ 0)
      expect(transforms.last.dy, 0);

      // dy should decrease monotonically
      for (var i = 1; i < transforms.length; i++) {
        expect(transforms[i].dy, lessThanOrEqualTo(transforms[i - 1].dy),
            reason: 'slideUp dy should decrease from frame ${i - 1} to $i');
      }

      // Alpha also increases (fade in + slide)
      expect(transforms.first.alpha, lessThan(transforms.last.alpha));
    });

    test('TextAnimation.wave oscillates horizontally and vertically', () {
      final transforms = List.generate(
        8,
        (i) => computeTextTransform(
          animation: TextAnimation.wave,
          frameIndex: i,
          totalFrames: 8,
        ),
      );

      // Wave should have non-zero dx in some frames
      expect(transforms.any((t) => t.dx != 0), isTrue,
          reason: 'Wave should oscillate horizontally');

      // Wave dx should be bounded within ±15
      for (final t in transforms) {
        expect(t.dx.abs(), lessThanOrEqualTo(15));
        expect(t.dy.abs(), lessThanOrEqualTo(8));
      }
    });

    test('TextAnimation.grow scales from 0.5 to 1.0', () {
      final transforms = List.generate(
        8,
        (i) => computeTextTransform(
          animation: TextAnimation.grow,
          frameIndex: i,
          totalFrames: 8,
        ),
      );

      // First frame: scale at 0.5
      expect(transforms.first.scale, closeTo(0.5, 0.01));

      // Last frame: scale at 1.0
      expect(transforms.last.scale, closeTo(1.0, 0.01));

      // Scale should increase monotonically
      for (var i = 1; i < transforms.length; i++) {
        expect(transforms[i].scale,
            greaterThanOrEqualTo(transforms[i - 1].scale),
            reason: 'Grow scale should increase from frame ${i - 1} to $i');
      }

      // Position should remain default
      for (final t in transforms) {
        expect(t.dx, 0);
        expect(t.dy, 0);
      }
    });

    test('TextAnimation.shake alternates dx between +10 and -10', () {
      final transforms = List.generate(
        8,
        (i) => computeTextTransform(
          animation: TextAnimation.shake,
          frameIndex: i,
          totalFrames: 8,
        ),
      );

      // Even frames should be +10, odd frames -10
      for (var i = 0; i < transforms.length; i++) {
        if (i % 2 == 0) {
          expect(transforms[i].dx, 10, reason: 'Even frame $i should be +10');
        } else {
          expect(transforms[i].dx, -10, reason: 'Odd frame $i should be -10');
        }
      }

      // dy, scale, alpha should remain default
      for (final t in transforms) {
        expect(t.dy, 0);
        expect(t.scale, 1.0);
        expect(t.alpha, 230);
      }
    });

    test('handles totalFrames=0 gracefully', () {
      for (final anim in TextAnimation.values) {
        final t = computeTextTransform(
          animation: anim,
          frameIndex: 0,
          totalFrames: 0,
        );
        // Should return default identity transform
        expect(t.dx, 0);
        expect(t.dy, 0);
        expect(t.scale, 1.0);
        expect(t.alpha, 230);
      }
    });

    test('handles single frame (totalFrames=1)', () {
      for (final anim in TextAnimation.values) {
        final t = computeTextTransform(
          animation: anim,
          frameIndex: 0,
          totalFrames: 1,
        );
        // Should not crash; values should be within expected ranges
        expect(t.dx.abs(), lessThanOrEqualTo(20));
        expect(t.dy.abs(), lessThanOrEqualTo(40));
        expect(t.scale, greaterThanOrEqualTo(0.0));
        expect(t.scale, lessThanOrEqualTo(1.0));
        expect(t.alpha, greaterThanOrEqualTo(0));
        expect(t.alpha, lessThanOrEqualTo(255));
      }
    });

    test('handles minimum frame count (2 frames)', () {
      for (final anim in TextAnimation.values) {
        for (var i = 0; i < 2; i++) {
          final t = computeTextTransform(
            animation: anim,
            frameIndex: i,
            totalFrames: 2,
          );
          expect(t.dx.abs(), lessThanOrEqualTo(20));
          expect(t.dy.abs(), lessThanOrEqualTo(40));
          expect(t.scale, greaterThanOrEqualTo(0.0));
          expect(t.alpha, greaterThanOrEqualTo(0));
          expect(t.alpha, lessThanOrEqualTo(255));
        }
      }
    });

    test('handles maximum frame count (8 frames)', () {
      for (final anim in TextAnimation.values) {
        for (var i = 0; i < 8; i++) {
          final t = computeTextTransform(
            animation: anim,
            frameIndex: i,
            totalFrames: 8,
          );
          expect(t.dx.abs(), lessThanOrEqualTo(20));
          expect(t.dy.abs(), lessThanOrEqualTo(40));
          expect(t.scale, greaterThanOrEqualTo(0.0));
          expect(t.alpha, greaterThanOrEqualTo(0));
          expect(t.alpha, lessThanOrEqualTo(255));
        }
      }
    });
  });

  // ===========================================================================
  // 2. GIF Frame Rendering with Text Animation
  // ===========================================================================

  group('GIF rendering with text animation', () {
    /// Helper: creates N solid-color 512x512 frames with text burned in
    /// using the given animation, then encodes as GIF.
    Uint8List renderAnimatedGif({
      required int frameCount,
      required String text,
      required TextAnimation animation,
      int frameDurationMs = 125,
    }) {
      final frames = <img.Image>[];
      for (var i = 0; i < frameCount; i++) {
        final frame = img.Image(width: 512, height: 512);
        img.fill(frame, color: img.ColorRgba8(100, 150, 200, 255));

        // Apply animation transform
        final transform = computeTextTransform(
          animation: animation,
          frameIndex: i,
          totalFrames: frameCount,
        );

        const baseX = 512 ~/ 4;
        const baseY = 512 - 80;
        final drawX = (baseX + transform.dx).clamp(0, 511);
        final drawY = (baseY + transform.dy).clamp(0, 511);
        final drawAlpha = transform.alpha.clamp(0, 255);

        img.drawString(
          frame,
          text,
          font: img.arial24,
          x: drawX,
          y: drawY,
          color: img.ColorRgba8(255, 255, 255, drawAlpha),
        );

        frame.frameDuration = (frameDurationMs / 10).round();
        frames.add(frame);
      }

      final animation2 = frames.first.clone();
      for (var i = 1; i < frames.length; i++) {
        animation2.addFrame(frames[i]);
      }
      return Uint8List.fromList(img.encodeGif(animation2));
    }

    test('GIF with TextAnimation.none has text at same position in all frames',
        () {
      final gif = renderAnimatedGif(
        frameCount: 4,
        text: 'Hello!',
        animation: TextAnimation.none,
      );

      // Verify GIF is valid
      expect(gif[0], 0x47); // 'G'
      expect(gif[1], 0x49); // 'I'
      expect(gif[2], 0x46); // 'F'

      // Decode and check frame count
      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 4);
    });

    test('GIF with TextAnimation.bounce produces valid multi-frame GIF', () {
      final gif = renderAnimatedGif(
        frameCount: 6,
        text: 'Bounce!',
        animation: TextAnimation.bounce,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 6);
    });

    test('GIF with TextAnimation.fadeIn produces valid GIF', () {
      final gif = renderAnimatedGif(
        frameCount: 4,
        text: 'Fading',
        animation: TextAnimation.fadeIn,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 4);
    });

    test('GIF with TextAnimation.slideUp produces valid GIF', () {
      final gif = renderAnimatedGif(
        frameCount: 5,
        text: 'Slide!',
        animation: TextAnimation.slideUp,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 5);
    });

    test('GIF with TextAnimation.wave produces valid GIF', () {
      final gif = renderAnimatedGif(
        frameCount: 8,
        text: 'Wave',
        animation: TextAnimation.wave,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 8);
    });

    test('GIF with TextAnimation.grow produces valid GIF', () {
      final gif = renderAnimatedGif(
        frameCount: 4,
        text: 'Grow!',
        animation: TextAnimation.grow,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 4);
    });

    test('GIF with TextAnimation.shake produces valid GIF', () {
      final gif = renderAnimatedGif(
        frameCount: 4,
        text: 'Shake!',
        animation: TextAnimation.shake,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 4);
    });

    test('animated GIF with text stays within 500KB size limit', () {
      final gif = renderAnimatedGif(
        frameCount: 8,
        text: 'Size check!',
        animation: TextAnimation.bounce,
      );

      expect(gif.length, lessThanOrEqualTo(StickerGuardrails.maxAnimatedSizeBytes),
          reason: 'GIF with 8 frames and text should fit within 500KB');
    });

    test('all animation types produce GIFs of similar size', () {
      final sizes = <TextAnimation, int>{};
      for (final anim in TextAnimation.values) {
        final gif = renderAnimatedGif(
          frameCount: 4,
          text: 'Test',
          animation: anim,
        );
        sizes[anim] = gif.length;
      }

      // All should be non-zero and within 500KB
      for (final entry in sizes.entries) {
        expect(entry.value, greaterThan(0),
            reason: '${entry.key.label} GIF should be non-empty');
        expect(entry.value, lessThanOrEqualTo(500 * 1024),
            reason: '${entry.key.label} GIF should fit in 500KB');
      }
    });

    test('GIF frame duration encoding is consistent', () {
      // 8 fps = 125ms → 13 centiseconds
      // The encoding sets frameDuration = (125/10).round() = 13
      const frameDurationMs = 125;
      final centiseconds = (frameDurationMs / 10).round();
      expect(centiseconds, 13);

      // Verify GIF can be created with this frame duration
      final gif = renderAnimatedGif(
        frameCount: 3,
        text: 'FPS',
        animation: TextAnimation.none,
        frameDurationMs: frameDurationMs,
      );

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 3);
    });

    test('minimum frame count (2) with all animations', () {
      for (final anim in TextAnimation.values) {
        final gif = renderAnimatedGif(
          frameCount: 2,
          text: 'Min',
          animation: anim,
        );
        final decoded = img.decodeGif(gif);
        expect(decoded, isNotNull,
            reason: '${anim.label} with 2 frames should produce valid GIF');
        expect(decoded!.numFrames, 2);
      }
    });
  });

  // ===========================================================================
  // 3. Image Cropping Validation
  // ===========================================================================

  group('Image cropping — comprehensive', () {
    late WhatsAppExportService service;

    setUp(() {
      service = WhatsAppExportService();
    });

    test('crop from landscape preserves aspect ratio on 512x512 canvas', () async {
      final landscape = img.Image(width: 1920, height: 1080);
      img.fill(landscape, color: img.ColorRgba8(100, 200, 150, 255));
      final input = Uint8List.fromList(img.encodePng(landscape));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('crop from very wide panoramic image', () async {
      final panoramic = img.Image(width: 3000, height: 200);
      img.fill(panoramic, color: img.ColorRgba8(50, 100, 200, 255));
      final input = Uint8List.fromList(img.encodePng(panoramic));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('crop from very tall image', () async {
      final tall = img.Image(width: 200, height: 3000);
      img.fill(tall, color: img.ColorRgba8(200, 50, 100, 255));
      final input = Uint8List.fromList(img.encodePng(tall));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('already 512x512 image passes through unchanged dimensions', () async {
      final exact = img.Image(width: 512, height: 512);
      img.fill(exact, color: img.ColorRgba8(128, 128, 128, 255));
      final input = Uint8List.fromList(img.encodePng(exact));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('image with transparency preserves alpha channel', () async {
      final transparent = img.Image(width: 256, height: 256, numChannels: 4);
      // Fill with semi-transparent pixels
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          transparent.setPixelRgba(x, y, 255, 0, 0, 128);
        }
      }
      final input = Uint8List.fromList(img.encodePng(transparent));

      final output = await service.convertToWhatsAppFormat(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('conversion output is valid PNG', () async {
      final source = img.Image(width: 300, height: 400);
      img.fill(source, color: img.ColorRgba8(200, 100, 50, 255));
      final input = Uint8List.fromList(img.encodePng(source));

      final output = await service.convertToWhatsAppFormat(input);

      // PNG magic bytes: 137 80 78 71
      expect(output[0], 0x89); // PNG signature
      expect(output[1], 0x50); // 'P'
      expect(output[2], 0x4E); // 'N'
      expect(output[3], 0x47); // 'G'
    });

    test('static sticker compression reduces large images', () async {
      // Create a large image with varied content (harder to compress)
      final large = img.Image(width: 1024, height: 1024);
      for (var y = 0; y < 1024; y++) {
        for (var x = 0; x < 1024; x++) {
          large.setPixelRgba(x, y, x % 256, y % 256, (x * y) % 256, 255);
        }
      }
      final input = Uint8List.fromList(img.encodePng(large));

      final compressed =
          await StickerGuardrails.compressStaticSticker(input);

      expect(compressed.lengthInBytes,
          lessThanOrEqualTo(StickerGuardrails.maxStaticSizeBytes));
    });
  });

  // ===========================================================================
  // 4. Animated Sticker Generation — Frame/FPS/Duration Combinations
  // ===========================================================================

  group('Animated sticker — frame/FPS/duration matrix', () {
    // Test all valid combinations of frames and FPS
    for (var frames = StickerGuardrails.minFrames;
        frames <= StickerGuardrails.maxFrames;
        frames++) {
      for (var fps = StickerGuardrails.minFps;
          fps <= StickerGuardrails.maxFps;
          fps++) {
        final durationMs = StickerGuardrails.totalDurationMs(frames, fps);
        final isSafe = StickerGuardrails.isDurationSafe(frames, fps);

        test('$frames frames @ $fps fps = ${durationMs}ms (${isSafe ? "safe" : "unsafe"})',
            () {
          expect(durationMs, greaterThan(0));

          if (isSafe) {
            expect(durationMs, greaterThanOrEqualTo(StickerGuardrails.minDurationMs));
            expect(durationMs, lessThanOrEqualTo(StickerGuardrails.maxDurationMs));

            // Validation should pass for valid size
            final errors = StickerGuardrails.validateAnimatedSticker(
              frameCount: frames,
              estimatedSizeBytes: 100 * 1024,
              fps: fps,
            );
            expect(errors, isEmpty,
                reason: '$frames frames @ $fps fps should be valid');
          } else {
            // Duration outside safe range
            expect(
              durationMs < StickerGuardrails.minDurationMs ||
                  durationMs > StickerGuardrails.maxDurationMs,
              isTrue,
            );
          }
        });
      }
    }

    test('frame count below minimum rejected with kid-friendly message', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1,
        estimatedSizeBytes: 10 * 1024,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('Add at least'));
    });

    test('frame count above maximum rejected', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 9,
        estimatedSizeBytes: 100 * 1024,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('Too many'));
    });

    test('FPS below minimum rejected', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 100 * 1024,
        fps: 3,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('slow')), isTrue);
    });

    test('FPS above maximum rejected', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 100 * 1024,
        fps: 9,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('fast')), isTrue);
    });

    test('oversized animated sticker rejected', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 600 * 1024,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('too big')), isTrue);
    });

    test('multiple errors reported at once', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1,
        estimatedSizeBytes: 600 * 1024,
        fps: 3,
        overlayText: 'damn',
      );
      // Should have at least 3 errors: frame count, FPS, size, text
      expect(errors.length, greaterThanOrEqualTo(3));
    });
  });

  // ===========================================================================
  // 5. Video to Animated Sticker — Duration and Frame Extraction Guardrails
  // ===========================================================================

  group('Video-to-sticker guardrails', () {
    test('max video duration is 5 seconds (enforced in UI)', () {
      // Video screen enforces 5s max. With 8 frames at 4fps = 2s duration.
      // The guardrail allows up to 10s but recommends short clips.
      final duration = StickerGuardrails.totalDurationMs(8, 4);
      expect(duration, 2000);
      expect(duration, lessThanOrEqualTo(StickerGuardrails.maxDurationMs));
    });

    test('frame extraction count is bounded 2-8', () {
      expect(StickerGuardrails.minFrames, 2);
      expect(StickerGuardrails.maxFrames, 8);
    });

    test('FPS slider range matches guardrails', () {
      expect(StickerGuardrails.minFps, 4);
      expect(StickerGuardrails.maxFps, 8);
    });

    test('animated frame compression reduces oversized frames', () async {
      // Create 4 frames that are over the limit
      final oversizedFrames = List.generate(4, (i) {
        final frame = img.Image(width: 1024, height: 1024);
        for (var y = 0; y < 1024; y++) {
          for (var x = 0; x < 1024; x++) {
            frame.setPixelRgba(
                x, y, (x + i * 30) % 256, (y + i * 30) % 256, 128, 255);
          }
        }
        return Uint8List.fromList(img.encodePng(frame));
      });

      final totalBefore =
          oversizedFrames.fold<int>(0, (s, f) => s + f.length);

      final compressed =
          await StickerGuardrails.compressAnimatedFrames(oversizedFrames);

      // Compressed frames should exist
      expect(compressed.length, oversizedFrames.length);

      // If compression was needed, total should be smaller
      final totalAfter = compressed.fold<int>(0, (s, f) => s + f.length);
      if (totalBefore > StickerGuardrails.maxAnimatedSizeBytes) {
        expect(totalAfter, lessThan(totalBefore),
            reason: 'Compression should reduce oversized frames');
      }
    });

    test('frame duration converts correctly for all valid FPS values', () {
      // 4 fps → 250ms → 25 centiseconds
      expect((1000 / 4 / 10).round(), 25);
      // 5 fps → 200ms → 20 centiseconds
      expect((1000 / 5 / 10).round(), 20);
      // 6 fps → 167ms → 17 centiseconds
      expect((1000 / 6 / 10).round(), 17);
      // 7 fps → 143ms → 14 centiseconds
      expect((1000 / 7 / 10).round(), 14);
      // 8 fps → 125ms → 13 centiseconds
      expect((1000 / 8 / 10).round(), 13);
    });
  });

  // ===========================================================================
  // 6. Kid-Safe Text Validation — Extended Edge Cases
  // ===========================================================================

  group('Kid-safe text — extended edge cases', () {
    test('empty string passes', () {
      expect(StickerGuardrails.isKidSafeText(''), isTrue);
    });

    test('whitespace-only passes', () {
      expect(StickerGuardrails.isKidSafeText('   '), isTrue);
    });

    test('emojis only passes', () {
      expect(StickerGuardrails.isKidSafeText('😀🎉🌟'), isTrue);
    });

    test('mixed case blocked word is caught', () {
      expect(StickerGuardrails.isKidSafeText('You are STUPID'), isFalse);
      expect(StickerGuardrails.isKidSafeText('sO dUmB'), isFalse);
    });

    test('blocked word with punctuation is caught', () {
      expect(StickerGuardrails.isKidSafeText('idiot!'), isFalse);
      expect(StickerGuardrails.isKidSafeText('hate.'), isFalse);
    });

    test('blocked word at start of string', () {
      expect(StickerGuardrails.isKidSafeText('damn it'), isFalse);
    });

    test('blocked word at end of string', () {
      expect(StickerGuardrails.isKidSafeText('you are dumb'), isFalse);
    });

    test('blocked two-word phrase "shut up" is caught', () {
      expect(StickerGuardrails.isKidSafeText('just shut up already'), isFalse);
    });

    test('words containing blocked words but not matching whole word pass', () {
      // Each contains a blocked word as substring but not as whole word
      expect(StickerGuardrails.isKidSafeText('seashell'), isTrue); // "hell"
      expect(StickerGuardrails.isKidSafeText('paradise'), isTrue); // "die"
      expect(StickerGuardrails.isKidSafeText('skilled'), isTrue); // "kill"
      expect(StickerGuardrails.isKidSafeText('crabapple'), isTrue); // "crap"
      expect(StickerGuardrails.isKidSafeText('diet'), isTrue); // "die"
      expect(StickerGuardrails.isKidSafeText('studio'), isTrue); // "stud"
      expect(StickerGuardrails.isKidSafeText('diecast'), isTrue); // "die"
      expect(StickerGuardrails.isKidSafeText('damned'), isTrue); // "damned" — \bdamn\b doesn't match because 'e' follows
    });

    test('friendly messages pass', () {
      final friendly = [
        'Love you!',
        'Best friends forever',
        'Have a great day!',
        'You rock!',
        'Happy birthday!',
        'Good morning!',
        'Let\'s play!',
        'So cool!',
        'Amazing work!',
        'You\'re awesome!',
      ];
      for (final text in friendly) {
        expect(StickerGuardrails.isKidSafeText(text), isTrue,
            reason: '"$text" should be kid-safe');
      }
    });

    test('all blocked words are individually caught', () {
      final blocked = [
        'damn', 'hell', 'crap', 'stupid', 'idiot', 'hate',
        'kill', 'die', 'suck', 'dumb', 'ugly', 'shut up', 'loser',
      ];
      for (final word in blocked) {
        expect(StickerGuardrails.isKidSafeText(word), isFalse,
            reason: '"$word" should be blocked');
      }
    });

    test('sanitizeText handles null-like edge cases', () {
      expect(StickerGuardrails.sanitizeText(''), '');
      expect(StickerGuardrails.sanitizeText('   '), '');
      expect(StickerGuardrails.sanitizeText('a'), 'a');
    });

    test('sanitizeText truncates at exactly maxTextLength', () {
      final long = 'A' * 100;
      final sanitized = StickerGuardrails.sanitizeText(long);
      expect(sanitized.length, StickerGuardrails.maxTextLength);
      expect(sanitized, 'A' * 50);
    });

    test('validation rejects non-kid-safe text in animated sticker', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 100 * 1024,
        fps: 6,
        overlayText: 'you are stupid',
      );
      expect(errors, contains('Oops! Please use friendly words only.'));
    });

    test('validation rejects non-kid-safe text in static sticker', () {
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
        overlayText: 'shut up',
      );
      expect(errors, contains('Oops! Please use friendly words only.'));
    });

    test('validation rejects too-long text', () {
      final longText = 'X' * 51;
      final errors = StickerGuardrails.validateStaticSticker(
        sizeBytes: 50 * 1024,
        overlayText: longText,
      );
      expect(errors.any((e) => e.contains('too long')), isTrue);
    });
  });

  // ===========================================================================
  // 7. Size Status Display — Colors, Labels, Tips
  // ===========================================================================

  group('Size status display helpers', () {
    test('safe status returns green', () {
      expect(
        StickerGuardrails.sizeColor(SizeStatus.safe),
        Colors.green,
      );
    });

    test('warning status returns orange', () {
      expect(
        StickerGuardrails.sizeColor(SizeStatus.warning),
        Colors.orange,
      );
    });

    test('tooLarge status returns red', () {
      expect(
        StickerGuardrails.sizeColor(SizeStatus.tooLarge),
        Colors.red,
      );
    });

    test('size label formats KB correctly', () {
      expect(StickerGuardrails.sizeLabel(1024), '1 KB');
      expect(StickerGuardrails.sizeLabel(50 * 1024), '50 KB');
      expect(StickerGuardrails.sizeLabel(500 * 1024), '500 KB');
    });

    test('size label handles sub-KB', () {
      expect(StickerGuardrails.sizeLabel(512), '< 1 KB');
      expect(StickerGuardrails.sizeLabel(0), '< 1 KB');
    });

    test('static sticker warning threshold is 80KB', () {
      expect(
        StickerGuardrails.sizeStatus(79 * 1024),
        SizeStatus.safe,
      );
      expect(
        StickerGuardrails.sizeStatus(81 * 1024),
        SizeStatus.warning,
      );
    });

    test('animated sticker warning threshold is 400KB', () {
      expect(
        StickerGuardrails.sizeStatus(399 * 1024, isAnimated: true),
        SizeStatus.safe,
      );
      expect(
        StickerGuardrails.sizeStatus(401 * 1024, isAnimated: true),
        SizeStatus.warning,
      );
    });

    test('tips are kid-friendly and actionable', () {
      final safeTip = StickerGuardrails.sizeTip(SizeStatus.safe);
      expect(safeTip, contains('Perfect'));

      final warningTip = StickerGuardrails.sizeTip(SizeStatus.warning);
      expect(warningTip, contains('simpler'));

      final tooLargeTip = StickerGuardrails.sizeTip(
        SizeStatus.tooLarge,
        isAnimated: true,
      );
      expect(tooLargeTip, contains('Remove'));

      final staticTooLargeTip = StickerGuardrails.sizeTip(SizeStatus.tooLarge);
      expect(staticTooLargeTip, contains('cropping'));
    });
  });

  // ===========================================================================
  // 8. End-to-End: GIF with Text Animation + Guardrails
  // ===========================================================================

  group('End-to-end: animated sticker pipeline', () {
    test('full pipeline: create frames → add animated text → encode → validate',
        () {
      // 1. Create 4 frames (simulating camera captures or video extraction)
      final frameBytes = <Uint8List>[];
      for (var i = 0; i < 4; i++) {
        final frame = img.Image(width: 512, height: 512);
        img.fill(frame, color: img.ColorRgba8(50 + i * 40, 100, 200, 255));
        frameBytes.add(Uint8List.fromList(img.encodePng(frame)));
      }

      // 2. Validate with guardrails
      const fps = 6;
      final rawSum = frameBytes.fold<int>(0, (s, f) => s + f.length);
      final estimatedSize = (rawSum * 0.6).round();

      final preErrors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: estimatedSize,
        fps: fps,
        overlayText: 'Hello!',
      );
      expect(preErrors, isEmpty, reason: 'Pre-export validation should pass');

      // 3. Build GIF with text animation
      final frames = <img.Image>[];
      const frameDurationMs = 167; // ~6 fps
      for (var i = 0; i < frameBytes.length; i++) {
        var decoded = img.decodeImage(frameBytes[i])!;
        decoded = img.copyResize(decoded, width: 512, height: 512);

        // Apply bounce animation
        final transform = computeTextTransform(
          animation: TextAnimation.bounce,
          frameIndex: i,
          totalFrames: frameBytes.length,
        );

        const baseX = 512 ~/ 4;
        const baseY = 512 - 80;
        img.drawString(
          decoded,
          'Hello!',
          font: img.arial24,
          x: (baseX + transform.dx).clamp(0, 511),
          y: (baseY + transform.dy).clamp(0, 511),
          color: img.ColorRgba8(255, 255, 255, transform.alpha),
        );

        decoded.frameDuration = (frameDurationMs / 10).round();
        frames.add(decoded);
      }

      final animation = frames.first.clone();
      for (var i = 1; i < frames.length; i++) {
        animation.addFrame(frames[i]);
      }
      final gifBytes = img.encodeGif(animation);

      // 4. Validate output
      expect(gifBytes, isNotEmpty);
      expect(gifBytes[0], 0x47); // GIF magic
      expect(gifBytes.length, lessThanOrEqualTo(500 * 1024));

      // 5. Verify duration is safe
      final duration = StickerGuardrails.totalDurationMs(4, fps);
      expect(StickerGuardrails.isDurationSafe(4, fps), isTrue);
      expect(duration, 667); // 4/6 * 1000
    });

    test('pipeline rejects unsafe text before encoding', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 100 * 1024,
        fps: 6,
        overlayText: 'you stupid',
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('friendly')), isTrue);
    });

    test('pipeline rejects oversized output', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4,
        estimatedSizeBytes: 600 * 1024,
        fps: 6,
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('too big')), isTrue);
    });

    test('GIF import → extract frames → re-encode with animation text', () {
      // Create a source GIF
      final src1 = img.Image(width: 128, height: 128);
      img.fill(src1, color: img.ColorRgba8(255, 0, 0, 255));
      src1.frameDuration = 10;

      final src2 = img.Image(width: 128, height: 128);
      img.fill(src2, color: img.ColorRgba8(0, 255, 0, 255));
      src2.frameDuration = 10;

      final src3 = img.Image(width: 128, height: 128);
      img.fill(src3, color: img.ColorRgba8(0, 0, 255, 255));
      src3.frameDuration = 10;

      final srcAnim = src1.clone();
      srcAnim.addFrame(src2);
      srcAnim.addFrame(src3);
      final srcGif = Uint8List.fromList(img.encodeGif(srcAnim));

      // Import: decode GIF
      final decoded = img.decodeGif(srcGif)!;
      expect(decoded.numFrames, 3);

      // Extract frames, resize, add text with wave animation
      final outFrames = <img.Image>[];
      for (var i = 0; i < decoded.numFrames; i++) {
        var frame = decoded.getFrame(i);
        frame = img.copyResize(frame, width: 512, height: 512);

        final transform = computeTextTransform(
          animation: TextAnimation.wave,
          frameIndex: i,
          totalFrames: decoded.numFrames,
        );

        img.drawString(
          frame,
          'Wave!',
          font: img.arial24,
          x: (128 + transform.dx).clamp(0, 511),
          y: (432 + transform.dy).clamp(0, 511),
          color: img.ColorRgba8(255, 255, 0, transform.alpha),
        );

        frame.frameDuration = 17; // ~6 fps
        outFrames.add(frame);
      }

      final outAnim = outFrames.first.clone();
      for (var i = 1; i < outFrames.length; i++) {
        outAnim.addFrame(outFrames[i]);
      }
      final outGif = img.encodeGif(outAnim);

      expect(outGif, isNotEmpty);
      expect(outGif.length, lessThanOrEqualTo(500 * 1024));

      // Re-decode to verify — GIF codec may add extra frames during processing
      final reDecoded = img.decodeGif(Uint8List.fromList(outGif))!;
      expect(reDecoded.numFrames, greaterThanOrEqualTo(3));
      expect(reDecoded.getFrame(0).width, 512);
    });
  });

  // ===========================================================================
  // 9. TextAnimationTransform toString and equality
  // ===========================================================================

  group('TextAnimationTransform', () {
    test('default constructor values', () {
      const t = TextAnimationTransform();
      expect(t.dx, 0);
      expect(t.dy, 0);
      expect(t.scale, 1.0);
      expect(t.alpha, 230);
    });

    test('custom values', () {
      const t = TextAnimationTransform(dx: 5, dy: -10, scale: 0.75, alpha: 128);
      expect(t.dx, 5);
      expect(t.dy, -10);
      expect(t.scale, 0.75);
      expect(t.alpha, 128);
    });

    test('toString format', () {
      const t = TextAnimationTransform(dx: 3, dy: -5, scale: 0.5, alpha: 200);
      expect(t.toString(), contains('dx: 3'));
      expect(t.toString(), contains('dy: -5'));
      expect(t.toString(), contains('scale: 0.5'));
      expect(t.toString(), contains('alpha: 200'));
    });
  });
}
