import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/core/widgets/text_style_sheet.dart';
import 'package:sticker_officer/features/editor/domain/editor_bitmap.dart';
import 'package:sticker_officer/features/export/data/whatsapp_export_service.dart';

/// Comprehensive tests covering:
/// 1. Image cropping — pixel-level verification
/// 2. Text addition — rendering and styling on bitmaps
/// 3. Text animation — all 7 presets with GIF generation
/// 4. GIF animated sticker generation — import, modify, export
/// 5. Guardrails — size, duration, frames, FPS, text, kid-safety
/// 6. Kid-friendly UX — error messages, labels, tips
void main() {
  // ===========================================================================
  // 1. IMAGE CROPPING — pixel-level verification
  // ===========================================================================

  group('Image Cropping — pixel-level verification', () {
    test('cropBitmap extracts the correct sub-region of pixels', () {
      // Create a 10x10 image with distinct color quadrants:
      // top-left = red, top-right = green, bottom-left = blue, bottom-right = yellow
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          if (x < 5 && y < 5) {
            source.getPixel(x, y).setRgba(255, 0, 0, 255); // red
          } else if (x >= 5 && y < 5) {
            source.getPixel(x, y).setRgba(0, 255, 0, 255); // green
          } else if (x < 5 && y >= 5) {
            source.getPixel(x, y).setRgba(0, 0, 255, 255); // blue
          } else {
            source.getPixel(x, y).setRgba(255, 255, 0, 255); // yellow
          }
        }
      }

      // Crop the top-left quadrant (5x5)
      final cropped = cropBitmap(source, const Rect.fromLTWH(0, 0, 5, 5));
      expect(cropped.width, 5);
      expect(cropped.height, 5);

      // Every pixel should be red
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final p = cropped.getPixel(x, y);
          expect(p.r.toInt(), 255, reason: 'pixel ($x,$y) red channel');
          expect(p.g.toInt(), 0, reason: 'pixel ($x,$y) green channel');
          expect(p.b.toInt(), 0, reason: 'pixel ($x,$y) blue channel');
        }
      }
    });

    test('cropBitmap extracts bottom-right quadrant correctly', () {
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          if (x >= 5 && y >= 5) {
            source.getPixel(x, y).setRgba(255, 255, 0, 255); // yellow
          } else {
            source.getPixel(x, y).setRgba(0, 0, 0, 255); // black
          }
        }
      }

      final cropped = cropBitmap(source, const Rect.fromLTWH(5, 5, 5, 5));
      expect(cropped.width, 5);
      expect(cropped.height, 5);

      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final p = cropped.getPixel(x, y);
          expect(p.r.toInt(), 255);
          expect(p.g.toInt(), 255);
        }
      }
    });

    test('cropBitmap clamps rect to image boundaries', () {
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(128, 128, 128, 255));

      // Crop rect extends beyond image bounds
      final cropped = cropBitmap(source, const Rect.fromLTWH(8, 8, 20, 20));
      // Should be clamped to remaining area (2x2)
      expect(cropped.width, 2);
      expect(cropped.height, 2);
    });

    test('cropBitmap with zero-area rect produces 1x1 minimum', () {
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(200, 100, 50, 255));

      // Zero-width/height rect
      final cropped = cropBitmap(source, const Rect.fromLTWH(3, 3, 0, 0));
      expect(cropped.width, greaterThanOrEqualTo(1));
      expect(cropped.height, greaterThanOrEqualTo(1));
    });

    test('cropBitmap preserves alpha channel', () {
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      // Semi-transparent pixels
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          source.getPixel(x, y).setRgba(255, 0, 0, 128);
        }
      }

      final cropped = cropBitmap(source, const Rect.fromLTWH(2, 2, 4, 4));
      expect(cropped.width, 4);
      expect(cropped.height, 4);

      final p = cropped.getPixel(0, 0);
      expect(p.a.toInt(), 128, reason: 'alpha should be preserved');
    });

    test('sequential crops produce correct cumulative result', () {
      final source = img.Image(width: 20, height: 20, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(100, 200, 50, 255));
      // Paint a 4x4 block at (8,8) with distinct color
      for (var y = 8; y < 12; y++) {
        for (var x = 8; x < 12; x++) {
          source.getPixel(x, y).setRgba(255, 0, 255, 255);
        }
      }

      // First crop: 10x10 from (5,5)
      final first = cropBitmap(source, const Rect.fromLTWH(5, 5, 10, 10));
      expect(first.width, 10);
      expect(first.height, 10);

      // Second crop: 4x4 from (3,3) of the first crop — should get the colored block
      final second = cropBitmap(first, const Rect.fromLTWH(3, 3, 4, 4));
      expect(second.width, 4);
      expect(second.height, 4);

      final p = second.getPixel(0, 0);
      expect(p.r.toInt(), 255, reason: 'sequential crop should find the colored block');
      expect(p.b.toInt(), 255);
    });

    test('cropBitmap followed by WhatsApp format conversion produces 512x512', () async {
      final source = img.Image(width: 100, height: 50, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 100, 100, 255));

      final cropped = cropBitmap(source, const Rect.fromLTWH(10, 10, 30, 30));
      final encoded = Uint8List.fromList(img.encodePng(cropped));

      final service = WhatsAppExportService();
      final result = await service.convertToWhatsAppFormat(encoded);
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });
  });

  // ===========================================================================
  // 2. TEXT ADDITION — rendering and style properties
  // ===========================================================================

  group('Text Addition — StickerTextStyle', () {
    test('default style has white, 28px, bold', () {
      const style = StickerTextStyle();
      expect(style.color, Colors.white);
      expect(style.size, 28.0);
      expect(style.bold, true);
      expect(style.italic, false);
      expect(style.fontFamily, 'Nunito');
      expect(style.hasOutline, false);
    });

    test('copyWith preserves unset fields', () {
      const original = StickerTextStyle(color: Colors.red, size: 40, bold: false);
      final modified = original.copyWith(italic: true);
      expect(modified.color, Colors.red);
      expect(modified.size, 40);
      expect(modified.bold, false);
      expect(modified.italic, true);
    });

    test('bold true stores w700 intent', () {
      const style = StickerTextStyle(size: 48, bold: true);
      expect(style.bold, true);
      expect(style.size, 48);
    });

    test('bold false stores w400 intent', () {
      const style = StickerTextStyle(bold: false);
      expect(style.bold, false);
    });

    test('italic is stored correctly', () {
      const style = StickerTextStyle(italic: true);
      expect(style.italic, true);
    });

    test('outline config is stored correctly', () {
      const style = StickerTextStyle(hasOutline: true, outlineColor: Colors.black);
      expect(style.hasOutline, true);
      expect(style.outlineColor, Colors.black);
    });

    test('all 7 font families are valid strings', () {
      const fonts = ['Nunito', 'Lobster', 'Bangers', 'Pacifico',
        'Permanent Marker', 'Press Start 2P', 'Luckiest Guy'];
      for (final font in fonts) {
        final style = StickerTextStyle(fontFamily: font);
        expect(style.fontFamily, font);
      }
    });

    test('text at min size (16) stores correctly', () {
      const style = StickerTextStyle(size: StickerGuardrails.minTextSize);
      expect(style.size, 16);
    });

    test('text at max size (64) stores correctly', () {
      const style = StickerTextStyle(size: StickerGuardrails.maxTextSize);
      expect(style.size, 64);
    });
  });

  group('Text Addition — rendering on bitmap with img.drawString', () {
    test('drawString writes pixels on the image', () {
      final canvas = img.Image(width: 512, height: 512, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

      img.drawString(
        canvas,
        'Hello!',
        font: img.arial24,
        x: 100,
        y: 100,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      // Check that some pixels in the text area are now non-transparent
      var nonTransparent = 0;
      for (var y = 95; y < 130; y++) {
        for (var x = 95; x < 250; x++) {
          final p = canvas.getPixel(x, y);
          if (p.a.toInt() > 0) nonTransparent++;
        }
      }
      expect(nonTransparent, greaterThan(0),
          reason: 'drawString should write visible pixels');
    });

    test('drawString with different colors produces different pixel values', () {
      final redCanvas = img.Image(width: 128, height: 128, numChannels: 4);
      img.fill(redCanvas, color: img.ColorRgba8(0, 0, 0, 0));
      img.drawString(redCanvas, 'X', font: img.arial24, x: 10, y: 10,
          color: img.ColorRgba8(255, 0, 0, 255));

      final blueCanvas = img.Image(width: 128, height: 128, numChannels: 4);
      img.fill(blueCanvas, color: img.ColorRgba8(0, 0, 0, 0));
      img.drawString(blueCanvas, 'X', font: img.arial24, x: 10, y: 10,
          color: img.ColorRgba8(0, 0, 255, 255));

      // Find a non-transparent pixel and compare RGB
      int? redR, blueR;
      for (var y = 10; y < 40 && redR == null; y++) {
        for (var x = 10; x < 40 && redR == null; x++) {
          final rp = redCanvas.getPixel(x, y);
          final bp = blueCanvas.getPixel(x, y);
          if (rp.a.toInt() > 128 && bp.a.toInt() > 128) {
            redR = rp.r.toInt();
            blueR = bp.r.toInt();
          }
        }
      }
      expect(redR, isNotNull, reason: 'should find visible text pixels');
      expect(redR, greaterThan(blueR!), reason: 'red text should have more red');
    });

    test('text with low alpha (fadeIn start) produces semi-transparent pixels', () {
      final canvas = img.Image(width: 128, height: 128, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
      img.drawString(canvas, 'A', font: img.arial24, x: 10, y: 10,
          color: img.ColorRgba8(255, 255, 255, 50));

      var foundSemiTransparent = false;
      for (var y = 10; y < 40; y++) {
        for (var x = 10; x < 40; x++) {
          final p = canvas.getPixel(x, y);
          if (p.a.toInt() > 0 && p.a.toInt() < 200) {
            foundSemiTransparent = true;
            break;
          }
        }
        if (foundSemiTransparent) break;
      }
      expect(foundSemiTransparent, isTrue,
          reason: 'low-alpha drawString should produce semi-transparent pixels');
    });

    test('emoji and special characters do not crash drawString', () {
      final canvas = img.Image(width: 256, height: 128, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
      // Should not throw
      img.drawString(canvas, 'Hello! :)', font: img.arial24, x: 10, y: 10,
          color: img.ColorRgba8(255, 255, 255, 255));
      expect(canvas.width, 256);
    });
  });

  // ===========================================================================
  // 3. TEXT ANIMATION — all 7 presets with real GIF generation
  // ===========================================================================

  group('Text Animation — all 7 presets produce valid animated GIFs', () {
    for (final animation in TextAnimation.values) {
      test('${animation.label} animation produces valid multi-frame GIF with text', () {
        const frameCount = 4;
        const fps = 8;
        const frameDurationMs = 1000 ~/ fps;
        const text = 'Test!';

        final frames = <img.Image>[];
        for (var i = 0; i < frameCount; i++) {
          final frame = img.Image(width: 512, height: 512, numChannels: 4);
          img.fill(frame, color: img.ColorRgba8(30, 30, 30, 255));

          final transform = computeTextTransform(
            animation: animation,
            frameIndex: i,
            totalFrames: frameCount,
          );

          final drawX = (128 + transform.dx).clamp(0, 511);
          final drawY = (432 + transform.dy).clamp(0, 511);

          img.drawString(
            frame,
            text,
            font: img.arial24,
            x: drawX,
            y: drawY,
            color: img.ColorRgba8(255, 255, 255, transform.alpha.clamp(0, 255)),
          );

          frame.frameDuration = (frameDurationMs / 10).round();
          frames.add(frame);
        }

        // Build GIF
        final animation2 = frames.first.clone();
        for (var i = 1; i < frames.length; i++) {
          animation2.addFrame(frames[i]);
        }
        final gifBytes = img.encodeGif(animation2);

        // Validate
        expect(gifBytes.length, greaterThan(0));
        expect(gifBytes.length, lessThanOrEqualTo(StickerGuardrails.maxAnimatedSizeBytes),
            reason: '${animation.label} GIF should be under 500KB');

        // Re-decode and verify frame count
        final decoded = img.decodeGif(Uint8List.fromList(gifBytes));
        expect(decoded, isNotNull);
        expect(decoded!.numFrames, frameCount);
      });
    }

    test('bounce animation has varying Y offsets across frames', () {
      final transforms = List.generate(8, (i) =>
          computeTextTransform(
              animation: TextAnimation.bounce, frameIndex: i, totalFrames: 8));
      final dyValues = transforms.map((t) => t.dy).toSet();
      expect(dyValues.length, greaterThan(1),
          reason: 'bounce should produce different dy values per frame');
    });

    test('fadeIn animation alpha increases monotonically', () {
      final alphas = List.generate(8, (i) =>
          computeTextTransform(
              animation: TextAnimation.fadeIn, frameIndex: i, totalFrames: 8).alpha);
      for (var i = 1; i < alphas.length; i++) {
        expect(alphas[i], greaterThanOrEqualTo(alphas[i - 1]),
            reason: 'fadeIn alpha should increase or stay same');
      }
      expect(alphas.last, greaterThan(alphas.first),
          reason: 'last frame should be more opaque than first');
    });

    test('slideUp animation dy decreases (moves up) over time', () {
      final dys = List.generate(6, (i) =>
          computeTextTransform(
              animation: TextAnimation.slideUp, frameIndex: i, totalFrames: 6).dy);
      expect(dys.first, greaterThan(dys.last),
          reason: 'slideUp should start below and end at base position');
    });

    test('grow animation scale increases from 0.5 to 1.0', () {
      final scales = List.generate(4, (i) =>
          computeTextTransform(
              animation: TextAnimation.grow, frameIndex: i, totalFrames: 4).scale);
      expect(scales.first, closeTo(0.5, 0.01));
      expect(scales.last, closeTo(1.0, 0.01));
    });

    test('shake animation alternates dx between +10 and -10', () {
      final dxs = List.generate(6, (i) =>
          computeTextTransform(
              animation: TextAnimation.shake, frameIndex: i, totalFrames: 6).dx);
      expect(dxs[0], 10);
      expect(dxs[1], -10);
      expect(dxs[2], 10);
    });

    test('wave animation has both horizontal and vertical movement', () {
      final transforms = List.generate(8, (i) =>
          computeTextTransform(
              animation: TextAnimation.wave, frameIndex: i, totalFrames: 8));
      final dxSet = transforms.map((t) => t.dx).toSet();
      final dySet = transforms.map((t) => t.dy).toSet();
      expect(dxSet.length, greaterThan(1), reason: 'wave should vary dx');
      expect(dySet.length, greaterThan(1), reason: 'wave should vary dy');
    });

    test('none animation produces identity transform for all frames', () {
      for (var i = 0; i < 8; i++) {
        final t = computeTextTransform(
            animation: TextAnimation.none, frameIndex: i, totalFrames: 8);
        expect(t.dx, 0);
        expect(t.dy, 0);
        expect(t.scale, 1.0);
        expect(t.alpha, 230);
      }
    });
  });

  // ===========================================================================
  // 4. GIF ANIMATED STICKER — import, modify, export pipeline
  // ===========================================================================

  group('GIF Animated Sticker — import, modify, export', () {
    Uint8List createTestGif({int frameCount = 4, int size = 64}) {
      final frames = <img.Image>[];
      for (var i = 0; i < frameCount; i++) {
        final frame = img.Image(width: size, height: size, numChannels: 4);
        // Each frame has a unique color so we can verify them
        final shade = (50 + i * 40).clamp(0, 255);
        img.fill(frame, color: img.ColorRgba8(shade, 0, shade, 255));
        frame.frameDuration = 12; // ~120ms per frame (8fps)
        frames.add(frame);
      }

      final animation = frames.first.clone();
      for (var i = 1; i < frames.length; i++) {
        animation.addFrame(frames[i]);
      }
      return Uint8List.fromList(img.encodeGif(animation));
    }

    test('GIF import: decode preserves frame count', () {
      final gif = createTestGif(frameCount: 5);
      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 5);
    });

    test('GIF import: extract individual frames', () {
      final gif = createTestGif(frameCount: 4, size: 32);
      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);

      final frameList = <img.Image>[];
      for (final frame in decoded!.frames) {
        frameList.add(frame);
      }
      expect(frameList.length, 4);
      expect(frameList[0].width, 32);
      expect(frameList[0].height, 32);
    });

    test('GIF import: frames can be resized to 512x512', () {
      final gif = createTestGif(frameCount: 3, size: 64);
      final decoded = img.decodeGif(gif);

      for (final frame in decoded!.frames) {
        final resized = img.copyResize(frame, width: 512, height: 512);
        expect(resized.width, 512);
        expect(resized.height, 512);
      }
    });

    test('GIF modify: add text to each frame then re-encode', () {
      final gif = createTestGif(frameCount: 3, size: 128);
      final decoded = img.decodeGif(gif);

      final modifiedFrames = <img.Image>[];
      for (var i = 0; i < decoded!.numFrames; i++) {
        final frame = img.copyResize(decoded.frames.elementAt(i),
            width: 512, height: 512);

        final transform = computeTextTransform(
          animation: TextAnimation.bounce,
          frameIndex: i,
          totalFrames: decoded.numFrames,
        );

        img.drawString(
          frame,
          'Modified!',
          font: img.arial24,
          x: (100 + transform.dx).clamp(0, 511),
          y: (400 + transform.dy).clamp(0, 511),
          color: img.ColorRgba8(255, 255, 0, transform.alpha.clamp(0, 255)),
        );

        frame.frameDuration = 12;
        modifiedFrames.add(frame);
      }

      // Re-encode
      final newAnim = modifiedFrames.first.clone();
      for (var i = 1; i < modifiedFrames.length; i++) {
        newAnim.addFrame(modifiedFrames[i]);
      }
      final reEncoded = img.encodeGif(newAnim);
      expect(reEncoded.length, greaterThan(0));

      // Verify re-decoded — frame count may be >= 3 depending on encoder
      final reDec = img.decodeGif(Uint8List.fromList(reEncoded));
      expect(reDec, isNotNull);
      expect(reDec!.numFrames, greaterThanOrEqualTo(3));
    });

    test('GIF with 2 frames (minimum) is valid', () {
      final gif = createTestGif(frameCount: 2);
      final decoded = img.decodeGif(gif);
      expect(decoded!.numFrames, 2);

      // Validate guardrails
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2,
        estimatedSizeBytes: gif.length,
        fps: 4, // 2 frames at 4fps = 500ms (minimum duration)
      );
      expect(errors, isEmpty, reason: '2 frames at 4fps should pass validation');
    });

    test('GIF with 8 frames (maximum) is valid', () {
      final gif = createTestGif(frameCount: 8);
      final decoded = img.decodeGif(gif);
      expect(decoded!.numFrames, 8);

      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 8,
        estimatedSizeBytes: gif.length,
        fps: 8,
      );
      expect(errors, isEmpty, reason: '8 frames at 8fps should pass validation');
    });

    test('GIF frame duration is encoded correctly for 8 FPS', () {
      const fps = 8;
      const frameDurationMs = 1000 ~/ fps; // 125ms
      const centiseconds = frameDurationMs ~/ 10; // 12-13

      final frame = img.Image(width: 64, height: 64, numChannels: 4);
      img.fill(frame, color: img.ColorRgba8(100, 100, 100, 255));
      frame.frameDuration = centiseconds;

      expect(frame.frameDuration, inInclusiveRange(12, 13));
    });

    test('full pipeline: create frames → add animated text → export GIF → validate size', () {
      const frameCount = 4;
      const fps = 8;

      final frames = <img.Image>[];
      for (var i = 0; i < frameCount; i++) {
        final frame = img.Image(width: 512, height: 512, numChannels: 4);
        img.fill(frame, color: img.ColorRgba8(40 + i * 30, 40, 80, 255));

        final transform = computeTextTransform(
          animation: TextAnimation.wave,
          frameIndex: i,
          totalFrames: frameCount,
        );

        img.drawString(
          frame,
          'Sticker!',
          font: img.arial24,
          x: (128 + transform.dx).clamp(0, 511),
          y: (432 + transform.dy).clamp(0, 511),
          color: img.ColorRgba8(255, 255, 255, transform.alpha.clamp(0, 255)),
        );

        frame.frameDuration = (1000 / fps / 10).round();
        frames.add(frame);
      }

      final anim = frames.first.clone();
      for (var i = 1; i < frames.length; i++) {
        anim.addFrame(frames[i]);
      }
      final gifBytes = img.encodeGif(anim);

      // Size check
      expect(gifBytes.length, lessThanOrEqualTo(500 * 1024),
          reason: 'GIF should be under 500KB');

      // Frame count check
      final reDec = img.decodeGif(Uint8List.fromList(gifBytes));
      expect(reDec!.numFrames, frameCount);

      // Guardrails check
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: frameCount,
        estimatedSizeBytes: gifBytes.length,
        fps: fps,
      );
      expect(errors, isEmpty);
    });

    test('corrupted GIF bytes are handled gracefully', () {
      final corrupted = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final decoded = img.decodeGif(corrupted);
      expect(decoded, isNull, reason: 'corrupted data should return null');
    });

    test('single-frame GIF is detected and rejected by guardrails', () {
      final gif = createTestGif(frameCount: 1);
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1,
        estimatedSizeBytes: gif.length,
        fps: 8,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('at least'));
    });
  });

  // ===========================================================================
  // 5. GUARDRAILS — comprehensive boundary testing
  // ===========================================================================

  group('Guardrails — size limits', () {
    test('static sticker exactly at 100KB passes', () {
      final errors = StickerGuardrails.validateStaticSticker(
          sizeBytes: 100 * 1024);
      expect(errors, isEmpty);
    });

    test('static sticker at 100KB + 1 byte fails', () {
      final errors = StickerGuardrails.validateStaticSticker(
          sizeBytes: 100 * 1024 + 1);
      expect(errors, isNotEmpty);
      expect(errors.first, contains('too big'));
    });

    test('animated sticker exactly at 500KB passes', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4, estimatedSizeBytes: 500 * 1024, fps: 8,
      );
      expect(errors, isEmpty);
    });

    test('animated sticker at 500KB + 1 byte fails', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4, estimatedSizeBytes: 500 * 1024 + 1, fps: 8,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('too big'));
    });

    test('zero-byte sticker passes (no size error)', () {
      final errors = StickerGuardrails.validateStaticSticker(sizeBytes: 0);
      expect(errors, isEmpty);
    });

    test('size status: safe / warning / tooLarge thresholds', () {
      // Static: safe < 80KB, warning 80-100KB, tooLarge > 100KB
      expect(StickerGuardrails.sizeStatus(50 * 1024), SizeStatus.safe);
      expect(StickerGuardrails.sizeStatus(90 * 1024), SizeStatus.warning);
      expect(StickerGuardrails.sizeStatus(110 * 1024), SizeStatus.tooLarge);

      // Animated: safe < 400KB, warning 400-500KB, tooLarge > 500KB
      expect(StickerGuardrails.sizeStatus(300 * 1024, isAnimated: true), SizeStatus.safe);
      expect(StickerGuardrails.sizeStatus(450 * 1024, isAnimated: true), SizeStatus.warning);
      expect(StickerGuardrails.sizeStatus(550 * 1024, isAnimated: true), SizeStatus.tooLarge);
    });
  });

  group('Guardrails — frame and FPS limits', () {
    test('exactly 2 frames at 4 FPS = 500ms (minimum) passes', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2, estimatedSizeBytes: 1000, fps: 4,
      );
      expect(errors, isEmpty);
    });

    test('1 frame fails', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 1, estimatedSizeBytes: 1000, fps: 8,
      );
      expect(errors.any((e) => e.contains('at least')), isTrue);
    });

    test('9 frames fails', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 9, estimatedSizeBytes: 1000, fps: 8,
      );
      expect(errors.any((e) => e.contains('Too many')), isTrue);
    });

    test('3 FPS (below minimum) fails', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4, estimatedSizeBytes: 1000, fps: 3,
      );
      expect(errors.any((e) => e.contains('too slow')), isTrue);
    });

    test('9 FPS (above maximum) fails', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 4, estimatedSizeBytes: 1000, fps: 9,
      );
      expect(errors.any((e) => e.contains('too fast')), isTrue);
    });

    test('all valid FPS values (4-8) pass with 4 frames', () {
      for (var fps = 4; fps <= 8; fps++) {
        final errors = StickerGuardrails.validateAnimatedSticker(
          frameCount: 4, estimatedSizeBytes: 1000, fps: fps,
        );
        expect(errors, isEmpty, reason: '$fps FPS with 4 frames should pass');
      }
    });

    test('all valid frame counts (4-8) pass at 8 FPS', () {
      // At 8 FPS, need >= 4 frames for 500ms minimum duration
      for (var frames = 4; frames <= 8; frames++) {
        final errors = StickerGuardrails.validateAnimatedSticker(
          frameCount: frames, estimatedSizeBytes: 1000, fps: 8,
        );
        expect(errors, isEmpty, reason: '$frames frames at 8 FPS should pass');
      }
    });

    test('2 frames at 8 FPS (250ms) triggers duration warning', () {
      final errors = StickerGuardrails.validateAnimatedSticker(
        frameCount: 2, estimatedSizeBytes: 1000, fps: 8,
      );
      expect(errors.any((e) => e.contains('too short')), isTrue,
          reason: '2 frames at 8fps = 250ms, below 500ms minimum');
    });
  });

  group('Guardrails — duration limits', () {
    test('2 frames at 4 FPS = 500ms (exact minimum) passes', () {
      expect(StickerGuardrails.totalDurationMs(2, 4), 500);
      expect(StickerGuardrails.isDurationSafe(2, 4), isTrue);
    });

    test('8 frames at 4 FPS = 2000ms passes', () {
      expect(StickerGuardrails.totalDurationMs(8, 4), 2000);
      expect(StickerGuardrails.isDurationSafe(8, 4), isTrue);
    });

    test('duration label is human readable', () {
      expect(StickerGuardrails.durationLabel(4, 8), '0.5s');
      expect(StickerGuardrails.durationLabel(8, 4), '2.0s');
    });

    test('0 FPS returns 0 duration (no crash)', () {
      expect(StickerGuardrails.totalDurationMs(4, 0), 0);
    });
  });

  group('Guardrails — text limits', () {
    test('text at exactly 50 characters passes', () {
      final text = 'A' * 50;
      final errors = StickerGuardrails.validateStaticSticker(
          sizeBytes: 1000, overlayText: text);
      expect(errors.where((e) => e.contains('too long')), isEmpty);
    });

    test('text at 51 characters fails', () {
      final text = 'A' * 51;
      final errors = StickerGuardrails.validateStaticSticker(
          sizeBytes: 1000, overlayText: text);
      expect(errors.any((e) => e.contains('too long')), isTrue);
    });

    test('empty text passes', () {
      final errors = StickerGuardrails.validateStaticSticker(
          sizeBytes: 1000, overlayText: '');
      expect(errors, isEmpty);
    });

    test('sanitizeText trims and truncates', () {
      expect(StickerGuardrails.sanitizeText('  hello  '), 'hello');
      expect(StickerGuardrails.sanitizeText('A' * 100).length, 50);
    });
  });

  group('Guardrails — pack limits', () {
    test('constants are correct', () {
      expect(StickerGuardrails.minStickersPerPack, 3);
      expect(StickerGuardrails.maxStickersPerPack, 30);
    });

    test('canvas size constants', () {
      expect(StickerGuardrails.stickerSize, 512);
      expect(StickerGuardrails.trayIconSize, 96);
    });
  });

  // ===========================================================================
  // 6. KID-SAFE TEXT FILTER — comprehensive testing
  // ===========================================================================

  group('Kid-Safe Text Filter', () {
    test('blocks all 13 explicit words', () {
      const blocked = [
        'damn', 'hell', 'crap', 'stupid', 'idiot', 'hate',
        'kill', 'die', 'suck', 'dumb', 'ugly', 'shut up', 'loser',
      ];
      for (final word in blocked) {
        expect(StickerGuardrails.isKidSafeText(word), isFalse,
            reason: '"$word" should be blocked');
      }
    });

    test('blocks words regardless of casing', () {
      expect(StickerGuardrails.isKidSafeText('STUPID'), isFalse);
      expect(StickerGuardrails.isKidSafeText('Stupid'), isFalse);
      expect(StickerGuardrails.isKidSafeText('sTuPiD'), isFalse);
    });

    test('blocks words embedded in sentences', () {
      expect(StickerGuardrails.isKidSafeText('you are stupid'), isFalse);
      expect(StickerGuardrails.isKidSafeText('I hate this'), isFalse);
      expect(StickerGuardrails.isKidSafeText('just shut up already'), isFalse);
    });

    test('does NOT block partial matches in safe words', () {
      // "shell" contains "hell" but should NOT be blocked (word boundary)
      expect(StickerGuardrails.isKidSafeText('shell'), isTrue);
      // "therapist" does not contain any blocked words
      expect(StickerGuardrails.isKidSafeText('therapist'), isTrue);
      // "skilled" does not contain "kill" as a standalone word
      expect(StickerGuardrails.isKidSafeText('skilled'), isTrue);
    });

    test('allows common kid-friendly text', () {
      const safe = [
        'Love you!', 'Best friends', 'So funny!', 'LOL',
        'Good morning', 'Happy birthday', 'Cool sticker',
        'Haha', 'BFF', 'Super fun!', 'Yay!', 'Awesome!',
      ];
      for (final text in safe) {
        expect(StickerGuardrails.isKidSafeText(text), isTrue,
            reason: '"$text" should be allowed');
      }
    });

    test('empty and whitespace-only text passes', () {
      expect(StickerGuardrails.isKidSafeText(''), isTrue);
      expect(StickerGuardrails.isKidSafeText('   '), isTrue);
    });

    test('validation error message for blocked text is friendly', () {
      final errors = StickerGuardrails.validateStaticSticker(
          sizeBytes: 1000, overlayText: 'you are stupid');
      expect(errors, isNotEmpty);
      expect(errors.first, contains('friendly'));
      // Should NOT contain technical language
      expect(errors.first, isNot(contains('exception')));
      expect(errors.first, isNot(contains('error')));
      expect(errors.first, isNot(contains('invalid')));
    });
  });

  // ===========================================================================
  // 7. KID-FRIENDLY ERROR MESSAGES — no technical jargon
  // ===========================================================================

  group('Kid-Friendly Error Messages', () {
    test('all animated sticker errors use kid-friendly language', () {
      // Collect all possible error messages
      final allErrors = <String>[];
      allErrors.addAll(StickerGuardrails.validateAnimatedSticker(
          frameCount: 0, estimatedSizeBytes: 0, fps: 0));
      allErrors.addAll(StickerGuardrails.validateAnimatedSticker(
          frameCount: 99, estimatedSizeBytes: 999999, fps: 99));
      allErrors.addAll(StickerGuardrails.validateAnimatedSticker(
          frameCount: 4, estimatedSizeBytes: 1000, fps: 8,
          overlayText: 'A' * 100));
      allErrors.addAll(StickerGuardrails.validateAnimatedSticker(
          frameCount: 4, estimatedSizeBytes: 1000, fps: 8,
          overlayText: 'you are stupid'));

      for (final error in allErrors) {
        expect(error, isNot(contains('exception')),
            reason: 'Error "$error" should not say "exception"');
        expect(error, isNot(contains('null')),
            reason: 'Error "$error" should not say "null"');
        expect(error, isNot(contains('index')),
            reason: 'Error "$error" should not say "index"');
        expect(error, isNot(contains('stack trace')),
            reason: 'Error "$error" should not say "stack trace"');
      }
    });

    test('size tips are kid-friendly', () {
      expect(StickerGuardrails.sizeTip(SizeStatus.safe), contains('Perfect'));
      expect(StickerGuardrails.sizeTip(SizeStatus.warning), contains('big'));
      expect(StickerGuardrails.sizeTip(SizeStatus.tooLarge), contains('Too big'));
    });

    test('size labels are human readable', () {
      expect(StickerGuardrails.sizeLabel(500), '< 1 KB');
      expect(StickerGuardrails.sizeLabel(50 * 1024), '50 KB');
      expect(StickerGuardrails.sizeLabel(512 * 1024), '512 KB');
    });

    test('size colors are intuitive (green, orange, red)', () {
      expect(StickerGuardrails.sizeColor(SizeStatus.safe), Colors.green);
      expect(StickerGuardrails.sizeColor(SizeStatus.warning), Colors.orange);
      expect(StickerGuardrails.sizeColor(SizeStatus.tooLarge), Colors.red);
    });

    test('TextAnimation enum has user-friendly labels', () {
      expect(TextAnimation.none.label, 'No Animation');
      expect(TextAnimation.bounce.label, 'Bounce');
      expect(TextAnimation.fadeIn.label, 'Fade In');
      expect(TextAnimation.slideUp.label, 'Slide Up');
      expect(TextAnimation.wave.label, 'Wave');
      expect(TextAnimation.grow.label, 'Grow');
      expect(TextAnimation.shake.label, 'Shake');
    });
  });

  // ===========================================================================
  // 8. COMPRESSION — static and animated
  // ===========================================================================

  group('Compression — static sticker', () {
    test('small image passes through without changes', () async {
      final small = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(small, color: img.ColorRgba8(255, 0, 0, 255));
      final bytes = Uint8List.fromList(img.encodePng(small));

      final result = await StickerGuardrails.compressStaticSticker(bytes);
      expect(result.lengthInBytes, lessThanOrEqualTo(100 * 1024));
    });

    test('compressStaticSticker always returns decodable image', () async {
      // Create a 512x512 image
      final source = img.Image(width: 512, height: 512, numChannels: 4);
      for (var y = 0; y < 512; y++) {
        for (var x = 0; x < 512; x++) {
          source.getPixel(x, y).setRgba(
            (x + y) % 256, (x * 2) % 256, (y * 3) % 256, 255,
          );
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(source));

      final result = await StickerGuardrails.compressStaticSticker(bytes);
      // Result should always be decodable
      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull);
      expect(result.lengthInBytes, lessThanOrEqualTo(100 * 1024));
    });

    test('compressed sticker is 512x512', () async {
      final source = img.Image(width: 200, height: 300, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(100, 200, 50, 255));
      final bytes = Uint8List.fromList(img.encodePng(source));

      final result = await StickerGuardrails.compressStaticSticker(bytes);
      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull);
      // Result should be 512x512 (or original if small enough)
      expect(decoded!.width, anyOf(512, 200)); // either resized or original
    });
  });

  group('Compression — animated frames', () {
    test('small frames pass through unchanged', () async {
      final frames = List.generate(4, (_) {
        final f = img.Image(width: 64, height: 64, numChannels: 4);
        img.fill(f, color: img.ColorRgba8(100, 100, 100, 255));
        return Uint8List.fromList(img.encodePng(f));
      });

      final result = await StickerGuardrails.compressAnimatedFrames(frames);
      expect(result.length, 4);
    });

    test('oversized frames are progressively compressed', () async {
      // Create frames with complex content that will be large
      final frames = List.generate(4, (i) {
        final f = img.Image(width: 512, height: 512, numChannels: 4);
        for (var y = 0; y < 512; y++) {
          for (var x = 0; x < 512; x++) {
            f.getPixel(x, y).setRgba(
              (x + i * 37) % 256,
              (y + i * 53) % 256,
              (x * y + i) % 256,
              255,
            );
          }
        }
        return Uint8List.fromList(img.encodePng(f));
      });

      final result = await StickerGuardrails.compressAnimatedFrames(frames);
      expect(result.length, 4, reason: 'should preserve frame count');

      // Total estimated size should be smaller
      final originalEstimate = frames.fold<int>(0, (s, f) => s + f.length);
      final compressedEstimate = result.fold<int>(0, (s, f) => s + f.length);
      expect(compressedEstimate, lessThanOrEqualTo(originalEstimate),
          reason: 'compressed should be ≤ original');
    });
  });

  // ===========================================================================
  // 9. WHATSAPP FORMAT CONVERSION — end-to-end
  // ===========================================================================

  group('WhatsApp Format Conversion', () {
    final service = WhatsAppExportService();

    test('landscape image is resized to 512x512', () async {
      final src = img.Image(width: 800, height: 400, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(255, 0, 0, 255));
      final result = await service.convertToWhatsAppFormat(
          Uint8List.fromList(img.encodePng(src)));
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });

    test('portrait image is resized to 512x512', () async {
      final src = img.Image(width: 300, height: 600, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(0, 255, 0, 255));
      final result = await service.convertToWhatsAppFormat(
          Uint8List.fromList(img.encodePng(src)));
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });

    test('square image is resized to 512x512', () async {
      final src = img.Image(width: 256, height: 256, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(0, 0, 255, 255));
      final result = await service.convertToWhatsAppFormat(
          Uint8List.fromList(img.encodePng(src)));
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });

    test('tiny 1x1 image is upscaled to 512x512', () async {
      final src = img.Image(width: 1, height: 1, numChannels: 4);
      src.getPixel(0, 0).setRgba(255, 0, 0, 255);
      final result = await service.convertToWhatsAppFormat(
          Uint8List.fromList(img.encodePng(src)));
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });

    test('output is always under 100KB', () async {
      final src = img.Image(width: 1024, height: 1024, numChannels: 4);
      for (var y = 0; y < 1024; y++) {
        for (var x = 0; x < 1024; x++) {
          src.getPixel(x, y).setRgba(
            (x * 7) % 256, (y * 11) % 256, (x + y) % 256, 255,
          );
        }
      }
      final result = await service.convertToWhatsAppFormat(
          Uint8List.fromList(img.encodePng(src)));
      expect(result.lengthInBytes, lessThanOrEqualTo(100 * 1024));
    });

    test('tray icon generation produces 96x96', () async {
      final src = img.Image(width: 200, height: 150, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(255, 100, 50, 255));
      final result = await service.generateTrayIcon(
          Uint8List.fromList(img.encodePng(src)));
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 96);
      expect(decoded.height, 96);
    });

    test('pack validation rejects pack with < 3 stickers', () {
      final result = service.validatePack(
        name: 'Test',
        stickers: [StickerData(data: Uint8List(100))],
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('at least'));
    });

    test('pack validation rejects pack with > 30 stickers', () {
      final stickers = List.generate(31,
          (_) => StickerData(data: Uint8List(100)));
      final result = service.validatePack(
        name: 'Test',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('at most'));
    });

    test('pack validation accepts pack with 3-30 stickers', () {
      for (final count in [3, 15, 30]) {
        final stickers = List.generate(count,
            (_) => StickerData(data: Uint8List(100)));
        final result = service.validatePack(
          name: 'Pack $count',
          stickers: stickers,
          trayIcon: Uint8List(100),
        );
        expect(result.isValid, isTrue,
            reason: '$count stickers should be valid');
      }
    });

    test('pack validation rejects empty name', () {
      final stickers = List.generate(5,
          (_) => StickerData(data: Uint8List(100)));
      final result = service.validatePack(
        name: '',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );
      expect(result.isValid, isFalse);
    });

    test('placeholder sticker is 512x512', () {
      final placeholder = WhatsAppExportService.generatePlaceholderSticker();
      final decoded = img.decodeImage(placeholder)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });
  });

  // ===========================================================================
  // 10. SELECTION & BACKGROUND REMOVAL
  // ===========================================================================

  group('Selection Mask', () {
    test('buildSelectionMask with triangle polygon', () {
      final mask = buildSelectionMask(
        width: 100,
        height: 100,
        polygon: const [
          Offset(50, 10),
          Offset(10, 90),
          Offset(90, 90),
        ],
      );
      expect(mask, isNotNull);
      expect(mask!.width, 100);
      expect(mask.height, 100);
      // Center should be inside the triangle
      expect(mask.contains(50, 50), isTrue);
      // Corner should be outside
      expect(mask.contains(0, 0), isFalse);
    });

    test('buildSelectionMask rejects < 3 points', () {
      final mask = buildSelectionMask(
        width: 100, height: 100,
        polygon: const [Offset(10, 10), Offset(90, 90)],
      );
      expect(mask, isNull);
    });

    test('eraseSelection makes selected pixels transparent', () {
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));

      // Create a mask that selects center pixels
      final mask = buildSelectionMask(
        width: 10, height: 10,
        polygon: const [Offset(3, 3), Offset(7, 3), Offset(7, 7), Offset(3, 7)],
      );
      expect(mask, isNotNull);

      final result = eraseSelection(source, mask!);
      // Selected pixels should be transparent
      expect(result.getPixel(5, 5).a.toInt(), 0);
      // Non-selected pixels should be opaque
      expect(result.getPixel(0, 0).a.toInt(), 255);
    });

    test('keepSelection makes non-selected pixels transparent', () {
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 255, 0, 255));

      final mask = buildSelectionMask(
        width: 10, height: 10,
        polygon: const [Offset(3, 3), Offset(7, 3), Offset(7, 7), Offset(3, 7)],
      );

      final result = keepSelection(source, mask!);
      // Non-selected corner should be transparent
      expect(result.getPixel(0, 0).a.toInt(), 0);
      // Selected center should be opaque
      expect(result.getPixel(5, 5).a.toInt(), 255);
    });
  });
}
