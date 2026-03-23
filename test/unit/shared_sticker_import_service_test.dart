import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:sticker_officer/features/import/data/shared_sticker_import_channel.dart';
import 'package:sticker_officer/features/import/data/shared_sticker_import_service.dart';

void main() {
  group('SharedStickerImportService', () {
    late Directory tempDir;
    late SharedStickerImportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shared_import_test');
      service = SharedStickerImportService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('imports valid shared image files into a sticker pack', () async {
      final source = File('${tempDir.path}/source.png');
      final image = img.Image(width: 64, height: 64);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      final encoded = img.encodePng(image);
      await source.writeAsBytes(encoded);

      final pack = await service.importFiles(
        [
          SharedStickerImportFile(
            path: source.path,
            mimeType: 'image/png',
            name: 'My Sticker.png',
          ),
        ],
        baseDirectory: '${tempDir.path}/pack_output',
      );

      expect(pack.stickerPaths, hasLength(1));
      expect(pack.trayIconPath, pack.stickerPaths.first);
      expect(pack.name, 'My Sticker');
      expect(File(pack.stickerPaths.first).existsSync(), isTrue);
    });

    test('throws when all shared files are invalid', () async {
      final source = File('${tempDir.path}/broken.bin');
      await source.writeAsString('not-an-image');

      await expectLater(
        () => service.importFiles(
          [
            SharedStickerImportFile(
              path: source.path,
              mimeType: 'application/octet-stream',
              name: 'broken.bin',
            ),
          ],
          baseDirectory: '${tempDir.path}/broken_pack',
        ),
        throwsA(isA<SharedStickerImportException>()),
      );
    });
  });
}
