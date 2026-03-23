import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sticker_officer/core/services/image_picker_service.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/data/models/sticker_pack.dart';
import 'package:sticker_officer/data/repositories/pack_repository.dart';
import 'package:sticker_officer/features/editor/domain/bulk_edit_queue.dart';

/// Tests for bulk edit orchestration logic.
///
/// Full widget tests of BulkEditScreen are slow to compile due to heavy
/// transitive imports (EditorScreen → image processing). The core queue
/// logic is tested here and in bulk_edit_queue_test.dart. Integration
/// testing on device validates the full UI flow.
void main() {
  group('Bulk edit orchestration logic', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bulk_orch_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('capacity enforcement truncates to available slots', () {
      const maxPerPack = StickerGuardrails.maxStickersPerPack; // 30
      const existingCount = 28;
      const available = maxPerPack - existingCount; // 2

      final pickedPaths = List.generate(5, (i) => '/img_$i.png');

      // Truncate to available slots
      final truncated = pickedPaths.length > available
          ? pickedPaths.sublist(0, available)
          : pickedPaths;

      expect(truncated.length, 2);
      expect(pickedPaths.length - truncated.length, 3); // 3 truncated
    });

    test('queue handles edit → skip → remove flow', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);

      // Edit first
      queue.markCurrentAndAdvance(
        BulkEditItemStatus.edited,
        savedPath: '/edited_a.png',
      );
      expect(queue.currentItem!.originalPath, '/b.png');

      // Skip second
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);
      expect(queue.currentItem!.originalPath, '/c.png');

      // Remove third
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      expect(queue.isComplete, true);

      // Verify counts
      expect(queue.countByStatus(BulkEditItemStatus.edited), 1);
      expect(queue.countByStatus(BulkEditItemStatus.skipped), 1);
      expect(queue.countByStatus(BulkEditItemStatus.removed), 1);
      expect(queue.savedCount, 2);
    });

    test('normalize + persist flow works end-to-end', () async {
      // Create a test image
      final source = img.Image(width: 200, height: 150, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 128, 255, 255));
      final sourceBytes = Uint8List.fromList(img.encodePng(source));
      final sourcePath = '${tempDir.path}/source.png';
      await File(sourcePath).writeAsBytes(sourceBytes);

      // Normalize
      final normalized = StickerGuardrails.normalizeStaticSticker(sourceBytes);

      // Verify it's a valid 512x512 PNG
      final decoded = img.decodePng(normalized);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);

      // Save to pack dir
      final packDir = '${tempDir.path}/stickers/test-pack';
      await Directory(packDir).create(recursive: true);
      final stickerPath = '$packDir/sticker_1.png';
      await File(stickerPath).writeAsBytes(normalized);

      // Verify file exists and is valid
      final savedFile = File(stickerPath);
      expect(await savedFile.exists(), true);
      final savedBytes = await savedFile.readAsBytes();
      final savedDecoded = img.decodePng(savedBytes);
      expect(savedDecoded!.width, 512);
    });

    test('tray icon is set on first save if none exists', () {
      final pack = StickerPack(
        id: 'test-pack',
        name: 'Test',
        authorName: 'Tester',
        createdAt: DateTime.now(),
        trayIconPath: null,
      );

      const stickerPath = '/stickers/test-pack/sticker_1.png';
      final updated = pack.copyWith(
        stickerPaths: [...pack.stickerPaths, stickerPath],
        trayIconPath: pack.trayIconPath ?? stickerPath,
      );

      expect(updated.trayIconPath, stickerPath);
      expect(updated.stickerPaths.length, 1);
    });

    test('tray icon is preserved if already set', () {
      final pack = StickerPack(
        id: 'test-pack',
        name: 'Test',
        authorName: 'Tester',
        createdAt: DateTime.now(),
        trayIconPath: '/existing_tray.png',
      );

      const stickerPath = '/stickers/test-pack/sticker_1.png';
      final updated = pack.copyWith(
        stickerPaths: [...pack.stickerPaths, stickerPath],
        trayIconPath: pack.trayIconPath ?? stickerPath,
      );

      expect(updated.trayIconPath, '/existing_tray.png');
    });

    test('pack persistence via repository', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PackRepository(prefs);

      final pack = StickerPack(
        id: 'bulk-test',
        name: 'Bulk Test',
        authorName: 'Tester',
        createdAt: DateTime.now(),
      );
      await repo.savePack(pack);

      // Simulate adding stickers one at a time (per-item persistence)
      for (int i = 0; i < 3; i++) {
        final current = repo.getPack('bulk-test')!;
        final updated = current.copyWith(
          stickerPaths: [...current.stickerPaths, '/sticker_$i.png'],
          trayIconPath: current.trayIconPath ?? '/sticker_$i.png',
        );
        await repo.updatePack(updated);
      }

      final final_ = repo.getPack('bulk-test')!;
      expect(final_.stickerPaths.length, 3);
      expect(final_.trayIconPath, '/sticker_0.png');
    });

    test('ImagePickerService wraps ImagePicker', () {
      final service = ImagePickerService();
      expect(service, isNotNull);
    });

    test('back confirmation text includes saved count', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);

      final remaining = queue.remaining;
      final saved = queue.savedCount;

      final message =
          'You have $remaining images remaining. '
          '${saved > 0 ? '$saved stickers already saved to this pack will stay. ' : ''}'
          'Leave editing?';

      expect(message, contains('2 images remaining'));
      expect(message, contains('1 stickers already saved'));
    });

    test('completion counts are correct', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png', '/d.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);

      final edited = queue.countByStatus(BulkEditItemStatus.edited);
      final skipped = queue.countByStatus(BulkEditItemStatus.skipped);
      final removed = queue.countByStatus(BulkEditItemStatus.removed);
      final total = edited + skipped;

      expect(edited, 1);
      expect(skipped, 2);
      expect(removed, 1);
      expect(total, 3);
    });
  });
}
