import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/features/editor/domain/editor_bitmap.dart';

void main() {
  group('editor bitmap helpers', () {
    test('buildSelectionMask fills the lasso polygon', () {
      final mask = buildSelectionMask(
        width: 24,
        height: 24,
        polygon: const [
          Offset(4, 4),
          Offset(19, 4),
          Offset(19, 19),
          Offset(4, 19),
        ],
      );

      expect(mask, isNotNull);
      expect(mask!.contains(10, 10), isTrue);
      expect(mask.contains(2, 2), isFalse);
      expect(mask.bounds.left, 4);
      expect(mask.bounds.top, 4);
      expect(mask.bounds.right, 20);
      expect(mask.bounds.bottom, 20);
    });

    test('applyStrokeToBitmap respects the active selection mask', () {
      final source = img.Image(width: 24, height: 24, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
      final mask =
          buildSelectionMask(
            width: 24,
            height: 24,
            polygon: const [
              Offset(0, 0),
              Offset(11, 0),
              Offset(11, 23),
              Offset(0, 23),
            ],
          )!;

      final result = applyStrokeToBitmap(
        source: source,
        points: const [Offset(2, 12), Offset(20, 12)],
        size: 6,
        color: img.ColorRgba8(255, 0, 0, 255),
        erase: false,
        selectionMask: mask,
      );

      final selectedPixel = result.getPixel(6, 12);
      final unselectedPixel = result.getPixel(18, 12);
      expect(selectedPixel.r.toInt(), greaterThan(selectedPixel.g.toInt()));
      expect(unselectedPixel.r.toInt(), 255);
      expect(unselectedPixel.g.toInt(), 255);
      expect(unselectedPixel.b.toInt(), 255);
    });

    test('applyStrokeToBitmap erases alpha along the stroke path', () {
      final source = img.Image(width: 24, height: 24, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));

      final result = applyStrokeToBitmap(
        source: source,
        points: const [Offset(4, 12), Offset(20, 12)],
        size: 8,
        color: img.ColorRgba8(0, 0, 0, 0),
        erase: true,
      );

      expect(result.getPixel(12, 12).a.toInt(), lessThan(20));
      expect(result.getPixel(12, 2).a.toInt(), 255);
    });

    test('cropBitmap returns the expected sub-rectangle', () {
      final source = img.Image(width: 40, height: 30, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(30, 40, 50, 255));
      source.setPixelRgba(12, 10, 255, 0, 0, 255);

      final cropped = cropBitmap(source, const Rect.fromLTWH(10, 8, 12, 10));

      expect(cropped.width, 12);
      expect(cropped.height, 10);
      expect(cropped.getPixel(2, 2).r.toInt(), 255);
    });

    test(
      'removeBackgroundFromEdges clears a flat border and keeps the subject',
      () {
        final source = img.Image(width: 32, height: 32, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(220, 230, 240, 255));

        for (var y = 10; y < 22; y++) {
          for (var x = 10; x < 22; x++) {
            source.setPixelRgba(x, y, 220, 40, 40, 255);
          }
        }

        final result = removeBackgroundFromEdges(source, tolerance: 18);

        expect(result.removedPixels, greaterThan(0));
        expect(result.image.getPixel(0, 0).a.toInt(), 0);
        expect(result.image.getPixel(16, 16).a.toInt(), 255);
        expect(result.image.getPixel(16, 16).r.toInt(), greaterThan(200));
      },
    );
  });
}
