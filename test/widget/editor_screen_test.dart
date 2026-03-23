import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/data/providers.dart';
import 'package:sticker_officer/features/editor/presentation/editor_screen.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/editor_toolbar.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sticker_packs': '[]'});
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    // Use a tall surface to avoid bottom-sheet overflow in tests
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pump();
  }

  // ===========================================================================
  // 1. Renders
  // ===========================================================================

  group('EditorScreen — renders', () {
    testWidgets('shows Sticker Editor title', (tester) async {
      await pumpEditor(tester);
      expect(find.text('Sticker Editor'), findsOneWidget);
    });

    testWidgets('shows toolbar', (tester) async {
      await pumpEditor(tester);
      expect(find.byType(EditorToolbar), findsOneWidget);
    });

    testWidgets('shows canvas', (tester) async {
      await pumpEditor(tester);
      expect(find.byType(EditorCanvas), findsOneWidget);
    });

    testWidgets('shows crop button with tooltip', (tester) async {
      await pumpEditor(tester);
      final crop = find.byIcon(Icons.crop_rounded);
      expect(crop, findsOneWidget);
      final btn = tester.widget<IconButton>(
        find.ancestor(of: crop, matching: find.byType(IconButton)),
      );
      expect(btn.tooltip, 'Crop Sticker');
    });

    testWidgets('shows undo and save buttons', (tester) async {
      await pumpEditor(tester);
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  // ===========================================================================
  // 2. Image cropping
  // ===========================================================================

  group('EditorScreen — crop', () {
    testWidgets('tapping crop without image shows snackbar', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.crop_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No image loaded to crop'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. Text addition
  // ===========================================================================

  group('EditorScreen — text addition', () {
    testWidgets('Text tool opens Add Text dialog', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      expect(find.text('Add Text'), findsOneWidget);
      expect(find.text('Type your text...'), findsOneWidget);
    });

    testWidgets('dialog has text field', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Cancel dismisses dialog', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Text'), findsNothing);
    });

    testWidgets('empty text does not open style sheet', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Style Your Text!'), findsNothing);
    });

    testWidgets('entering text and tapping Add opens style sheet',
        (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hello Kids!');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Pick a Color'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Bold'), findsOneWidget);
      expect(find.text('Add to Sticker!'), findsOneWidget);
    });

    testWidgets('style sheet has slider', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Test');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('style sheet shows text preview', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Preview Me');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Preview Me'), findsOneWidget);
    });

    testWidgets('bold toggle starts as ON', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bold');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('B  ON'), findsOneWidget);
    });

    testWidgets('tapping bold toggle switches to OFF', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Toggle');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      expect(find.text('B  OFF'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. Toolbar
  // ===========================================================================

  group('EditorScreen — toolbar', () {
    testWidgets('all 8 tool buttons visible', (tester) async {
      await pumpEditor(tester);
      expect(find.text('AI Magic \u{2728}'), findsOneWidget);
      expect(find.text('Lasso \u{1FA82}'), findsOneWidget);
      expect(find.text('Brush \u{1F3A8}'), findsOneWidget);
      expect(find.text('Magic Eraser'), findsOneWidget);
      expect(find.text('Text \u{1F4AC}'), findsOneWidget);
      expect(find.text('Style \u{1F308}'), findsOneWidget);
      expect(find.text('Caption \u{1F4DD}'), findsOneWidget);
      expect(find.text('Move \u{1F449}'), findsOneWidget);
    });

    testWidgets('AI caption opens suggestions', (tester) async {
      await pumpEditor(tester);
      // Scroll toolbar to reveal Caption button
      await tester.scrollUntilVisible(
        find.text('Caption \u{1F4DD}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption \u{1F4DD}'));
      await tester.pumpAndSettle();
      expect(find.text('AI Caption Suggestions'), findsOneWidget);
      expect(find.text('LOL \u{1F602}'), findsOneWidget);
    });

    testWidgets('AI style shows error without image', (tester) async {
      await pumpEditor(tester);
      await tester.scrollUntilVisible(
        find.text('Style \u{1F308}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Style \u{1F308}'));
      await tester.pumpAndSettle();
      // No image loaded — shows error snackbar
      expect(find.text('Load an image first to apply styles'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. Save flow
  // ===========================================================================

  group('EditorScreen — save', () {
    testWidgets('check button opens Save Sticker sheet', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Save Sticker'), findsOneWidget);
      expect(find.text('Save to Pack'), findsOneWidget);
      expect(find.text('Add to WhatsApp'), findsOneWidget);
    });
  });
}
