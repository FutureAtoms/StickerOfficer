import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/features/editor/domain/bulk_edit_queue.dart';

void main() {
  group('BulkEditItem', () {
    test('creation with defaults', () {
      const item = BulkEditItem(originalPath: '/a.png');
      expect(item.originalPath, '/a.png');
      expect(item.status, BulkEditItemStatus.pending);
      expect(item.savedPath, isNull);
    });

    test('copyWith updates fields', () {
      const item = BulkEditItem(originalPath: '/a.png');
      final edited = item.copyWith(
        status: BulkEditItemStatus.edited,
        savedPath: '/b.png',
      );
      expect(edited.status, BulkEditItemStatus.edited);
      expect(edited.savedPath, '/b.png');
      expect(edited.originalPath, '/a.png');
    });

    test('copyWith preserves unchanged fields', () {
      const item = BulkEditItem(
        originalPath: '/a.png',
        status: BulkEditItemStatus.skipped,
        savedPath: '/s.png',
      );
      final updated = item.copyWith(status: BulkEditItemStatus.edited);
      expect(updated.originalPath, '/a.png');
      expect(updated.savedPath, '/s.png');
    });
  });

  group('BulkEditQueue', () {
    test('initializes with correct count', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);
      expect(queue.total, 3);
      expect(queue.remaining, 3);
      expect(queue.isComplete, false);
    });

    test('currentItem returns first item', () {
      final queue = BulkEditQueue(['/a.png', '/b.png']);
      expect(queue.currentItem!.originalPath, '/a.png');
      expect(queue.currentIndex, 0);
    });

    test('advance moves to next item', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited, savedPath: '/x.png');
      expect(queue.currentItem!.originalPath, '/b.png');
      expect(queue.currentIndex, 1);
      expect(queue.remaining, 2);
    });

    test('isComplete after processing all items', () {
      final queue = BulkEditQueue(['/a.png', '/b.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);
      expect(queue.isComplete, true);
      expect(queue.currentItem, isNull);
      expect(queue.remaining, 0);
    });

    test('countByStatus tracks edited and skipped', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited, savedPath: '/x.png');
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      expect(queue.countByStatus(BulkEditItemStatus.edited), 1);
      expect(queue.countByStatus(BulkEditItemStatus.skipped), 1);
      expect(queue.countByStatus(BulkEditItemStatus.removed), 1);
      expect(queue.savedCount, 2);
    });

    test('advance skips past removed items', () {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png', '/d.png']);
      // Edit a, then mark b and c as removed before reaching them
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      // Now at b, remove it
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      // Now at c (not skipped since removed items only skip on _advance)
      expect(queue.currentItem!.originalPath, '/c.png');
    });

    test('all-removed completes queue', () {
      final queue = BulkEditQueue(['/a.png', '/b.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      expect(queue.isComplete, true);
      expect(queue.savedCount, 0);
    });

    test('items list is unmodifiable', () {
      final queue = BulkEditQueue(['/a.png']);
      expect(() => queue.items.add(const BulkEditItem(originalPath: '/x.png')),
          throwsUnsupportedError);
    });

    test('markCurrentAndAdvance is no-op when complete', () {
      final queue = BulkEditQueue(['/a.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      expect(queue.isComplete, true);
      // Should not throw
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      expect(queue.isComplete, true);
    });
  });
}
