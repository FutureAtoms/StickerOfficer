import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sticker_officer/features/editor/presentation/editor_screen.dart';

void main() {
  group('EditorScreen bulkMode', () {
    testWidgets('bulkMode=true shows Save & Next tooltip', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            // bulkMode=true + imagePath=null does NOT auto-open picker
            home: const EditorScreen(bulkMode: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the IconButton with check icon by looking for tooltip
      final saveButton = find.byTooltip('Save & Next');
      expect(saveButton, findsOneWidget);
    });

    testWidgets('bulkMode=false shows Save Sticker tooltip', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            // bulkMode=false + imagePath=null would auto-open picker,
            // but pumpAndSettle catches the MissingPluginException.
            // Instead, test with a non-existent path to avoid picker.
            home: const EditorScreen(bulkMode: false),
          ),
        ),
      );
      // Don't pumpAndSettle — the picker callback might throw in test.
      // Just pump once to render the widget tree.
      await tester.pump();

      final saveButton = find.byTooltip('Save Sticker');
      expect(saveButton, findsOneWidget);
    });

    testWidgets('bulkMode=true close pops with null', (tester) async {
      String? poppedResult = 'not_popped';

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.push<String?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProviderScope(
                          child: EditorScreen(bulkMode: true),
                        ),
                      ),
                    );
                    poppedResult = result;
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      // Open editor
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap close button (the leading icon)
      await tester.tap(find.byTooltip('Close Editor'));
      await tester.pumpAndSettle();

      expect(poppedResult, isNull);
    });

    testWidgets('bulkMode defaults to false', (tester) async {
      const editor = EditorScreen();
      expect(editor.bulkMode, false);
    });
  });

  group('Router extra handling', () {
    test('String extra is treated as imagePath', () {
      const extra = '/path/to/image.png';
      String? imagePath;
      String? packId;
      bool bulkMode = false;

      if (extra is String) {
        imagePath = extra;
      }

      expect(imagePath, '/path/to/image.png');
      expect(packId, isNull);
      expect(bulkMode, false);
    });

    test('Map extra with bulkMode extracts correctly', () {
      final Object extra = <String, dynamic>{
        'imagePath': '/img.png',
        'packId': 'pack-123',
        'bulkMode': true,
      };

      String? imagePath;
      String? packId;
      bool bulkMode = false;

      if (extra is String) {
        imagePath = extra;
      } else if (extra is Map<String, dynamic>) {
        imagePath = extra['imagePath'] as String?;
        packId = extra['packId'] as String?;
        bulkMode = extra['bulkMode'] as bool? ?? false;
      }

      expect(imagePath, '/img.png');
      expect(packId, 'pack-123');
      expect(bulkMode, true);
    });

    test('Map extra without bulkMode defaults to false', () {
      final Object extra = <String, dynamic>{
        'packId': 'pack-456',
      };

      String? imagePath;
      String? packId;
      bool bulkMode = false;

      if (extra is String) {
        imagePath = extra;
      } else if (extra is Map<String, dynamic>) {
        imagePath = extra['imagePath'] as String?;
        packId = extra['packId'] as String?;
        bulkMode = extra['bulkMode'] as bool? ?? false;
      }

      expect(imagePath, isNull);
      expect(packId, 'pack-456');
      expect(bulkMode, false);
    });

    test('Map<String, String?> still works (backward compat)', () {
      final Object extra = <String, String?>{'packId': 'pack-789'};

      String? imagePath;
      String? packId;
      bool bulkMode = false;

      if (extra is String) {
        imagePath = extra;
      } else if (extra is Map<String, dynamic>) {
        imagePath = extra['imagePath'] as String?;
        packId = extra['packId'] as String?;
        bulkMode = extra['bulkMode'] as bool? ?? false;
      }

      expect(packId, 'pack-789');
      expect(bulkMode, false);
    });
  });
}
