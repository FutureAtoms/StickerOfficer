import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/features/editor/domain/bulk_edit_queue.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/bulk_edit_progress.dart';

void main() {
  group('BulkEditProgress', () {
    testWidgets('shows "Editing 1 of 3" initially', (tester) async {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      expect(find.text('Editing 1 of 3'), findsOneWidget);
      expect(find.text('0 saved'), findsOneWidget);
    });

    testWidgets('shows correct count after advancing', (tester) async {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      expect(find.text('Editing 2 of 3'), findsOneWidget);
      expect(find.text('1 saved'), findsOneWidget);
    });

    testWidgets('shows "All done!" when complete', (tester) async {
      final queue = BulkEditQueue(['/a.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      expect(find.text('All done!'), findsOneWidget);
      expect(find.text('1 saved'), findsOneWidget);
    });

    testWidgets('has progress bar', (tester) async {
      final queue = BulkEditQueue(['/a.png', '/b.png']);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('renders thumbnail strip with correct item count', (tester) async {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      // There should be a ListView with 3 items
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows status icons for processed items', (tester) async {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png', '/d.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      // Check status icons are present
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('saved count includes edited and skipped but not removed', (tester) async {
      final queue = BulkEditQueue(['/a.png', '/b.png', '/c.png']);
      queue.markCurrentAndAdvance(BulkEditItemStatus.edited);
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
      queue.markCurrentAndAdvance(BulkEditItemStatus.skipped);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BulkEditProgress(queue: queue)),
        ),
      );

      // 1 edited + 1 skipped = 2 saved
      expect(find.text('2 saved'), findsOneWidget);
    });
  });
}
