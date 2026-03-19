// ignore_for_file: avoid_print
/// Processes downloaded meme images: resize to 512x512 with transparent
/// background, and distribute into 5 sticker packs of 30 each.
///
/// Run: dart run tool/process_meme_images.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final inputDir = '/tmp/meme_downloads';
  final outputDir = 'assets/seed_stickers';
  const size = 512;

  // Pack assignments: 30 images each
  final packs = [
    'brainrot_memes',   // 1-30: Mixed memes + Doge (internet culture)
    'reaction_memes',   // 31-60: Derp + Grumpy Cat + Bad Luck Brian (reactions)
    'ai_tech_memes',    // 61-90: Just Do It + Cash Me + Gabe + Lemme Smash
    'wholesome_memes',  // 91-120: Gaben + Emoji + Cats (cute/wholesome)
    'daily_life_memes', // 121-150: Dogs + Pizza + Coffee (daily life)
  ];

  var totalProcessed = 0;

  for (var packIdx = 0; packIdx < packs.length; packIdx++) {
    final prefix = packs[packIdx];
    final startNum = packIdx * 30 + 1;
    print('Processing pack: $prefix (images $startNum-${startNum + 29})');

    for (var i = 0; i < 30; i++) {
      final srcNum = startNum + i;
      final srcPath = '$inputDir/meme_${srcNum.toString().padLeft(3, '0')}.png';
      final dstPath = '$outputDir/${prefix}_${i + 1}.png';

      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) {
        print('  SKIP: $srcPath not found');
        continue;
      }

      try {
        final bytes = srcFile.readAsBytesSync();
        var decoded = img.decodeImage(bytes);
        if (decoded == null) {
          print('  SKIP: Could not decode $srcPath');
          continue;
        }

        // Resize maintaining aspect ratio, center on 512x512 transparent canvas
        final scale = size /
            (decoded.width > decoded.height
                ? decoded.width
                : decoded.height);
        final newW = (decoded.width * scale).round().clamp(1, size);
        final newH = (decoded.height * scale).round().clamp(1, size);

        final resized = img.copyResize(
          decoded,
          width: newW,
          height: newH,
          interpolation: img.Interpolation.linear,
        );

        // Create transparent 512x512 canvas
        final canvas = img.Image(width: size, height: size, numChannels: 4);
        img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

        // Center the resized image
        final offsetX = (size - newW) ~/ 2;
        final offsetY = (size - newH) ~/ 2;
        img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

        // Save
        final pngBytes = img.encodePng(canvas);
        File(dstPath).writeAsBytesSync(pngBytes);
        totalProcessed++;
      } catch (e) {
        print('  ERROR: $srcPath - $e');
      }
    }
    print('  Done');
  }

  print('\nTotal processed: $totalProcessed / 150');
}
