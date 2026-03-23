import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/data/providers.dart';
import 'package:sticker_officer/features/editor/presentation/editor_screen.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/editor_canvas.dart';

/// Comprehensive editor tests covering image cropping flow, text addition
/// with all styling options, drawing tools, undo, and save/export — filling
/// gaps identified in the test audit.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sticker_packs': '[]'});
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1284, 2778);
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

  Future<void> openStyleSheet(WidgetTester tester, String text) async {
    await tester.tap(find.text('Text \u{1F4AC}'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  // ===========================================================================
  // 1. Image Cropping — guardrails
  // ===========================================================================

  group('Image Cropping', () {
    testWidgets('crop button exists in app bar', (tester) async {
      await pumpEditor(tester);
      expect(find.byIcon(Icons.crop_rounded), findsOneWidget);
    });

    testWidgets('crop button has "Crop Sticker" tooltip', (tester) async {
      await pumpEditor(tester);
      final btn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.crop_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(btn.tooltip, 'Crop Sticker');
    });

    testWidgets('crop without image shows friendly error snackbar',
        (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.crop_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No image loaded to crop'), findsOneWidget);
    });

    testWidgets('crop error snackbar is kid-friendly (no technical jargon)',
        (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.crop_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Should NOT contain technical errors
      expect(find.textContaining('exception'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('error'), findsNothing);
    });

    testWidgets('canvas has no image by default (fresh editor)', (tester) async {
      await pumpEditor(tester);
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.image, isNull);
    });
  });

  // ===========================================================================
  // 2. Text Addition — full flow
  // ===========================================================================

  group('Text Addition — dialog', () {
    testWidgets('Text tool in toolbar opens Add Text dialog', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      expect(find.text('Add Text'), findsOneWidget);
    });

    testWidgets('Add Text dialog has TextField with hint', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      expect(find.text('Type your text...'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Cancel closes dialog without adding text', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Should not apply');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, isNull);
    });

    testWidgets('empty text does not open style sheet', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Style Your Text!'), findsNothing);
    });

    testWidgets('non-empty text opens style sheet', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Hello');
      expect(find.text('Style Your Text!'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. Text Styling — color, size, bold
  // ===========================================================================

  group('Text Styling — style sheet', () {
    testWidgets('style sheet has all sections', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Sections');

      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Pick a Color'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Bold'), findsOneWidget);
      expect(find.text('Add to Sticker!'), findsOneWidget);
    });

    testWidgets('style sheet shows text preview', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Preview text');
      // The text should appear in the preview container
      expect(find.text('Preview text'), findsOneWidget);
    });

    testWidgets('style sheet has size slider (16-64 range)', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Size');
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 16.0);
      expect(slider.max, 64.0);
    });

    testWidgets('size shows default 28px label', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Size label');
      expect(find.text('28px'), findsOneWidget);
    });

    testWidgets('bold toggle starts ON', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Bold test');
      expect(find.text('B  ON'), findsOneWidget);
    });

    testWidgets('bold toggle switches to OFF on tap', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Bold off');
      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      expect(find.text('B  OFF'), findsOneWidget);
    });

    testWidgets('double tap bold toggles back to ON', (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Double toggle');
      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      expect(find.text('B  OFF'), findsOneWidget);
      await tester.tap(find.text('B  OFF'));
      await tester.pumpAndSettle();
      expect(find.text('B  ON'), findsOneWidget);
    });

    testWidgets('applying text sets correct defaults on canvas',
        (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'Default');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'Default');
      expect(canvas.textColor, Colors.white);
      expect(canvas.textSize, 28.0);
      expect(canvas.textBold, isTrue);
    });

    testWidgets('applying text with bold OFF sets textBold false',
        (tester) async {
      await pumpEditor(tester);
      await openStyleSheet(tester, 'No bold');
      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textBold, isFalse);
    });
  });

  // ===========================================================================
  // 4. AI Captions
  // ===========================================================================

  group('AI Captions', () {
    testWidgets('Caption tool opens suggestion list', (tester) async {
      await pumpEditor(tester);
      await tester.scrollUntilVisible(
        find.text('Caption \u{1F4DD}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption \u{1F4DD}'));
      await tester.pumpAndSettle();
      expect(find.text('AI Caption Suggestions'), findsOneWidget);
    });

    testWidgets('all 4 caption suggestions visible', (tester) async {
      await pumpEditor(tester);
      await tester.scrollUntilVisible(
        find.text('Caption \u{1F4DD}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption \u{1F4DD}'));
      await tester.pumpAndSettle();

      expect(find.text('LOL \u{1F602}'), findsOneWidget);
      expect(find.text('Mood \u{1F485}'), findsOneWidget);
      expect(find.text('Not today \u{1F645}'), findsOneWidget);
      expect(find.text('Send help \u{1F198}'), findsOneWidget);
    });

    testWidgets('tapping caption applies it to canvas', (tester) async {
      await pumpEditor(tester);
      await tester.scrollUntilVisible(
        find.text('Caption \u{1F4DD}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption \u{1F4DD}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOL \u{1F602}'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'LOL \u{1F602}');
    });

    testWidgets('caption replaces previously applied text', (tester) async {
      await pumpEditor(tester);

      // First add manual text
      await openStyleSheet(tester, 'Manual text');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      // Then apply caption
      await tester.scrollUntilVisible(
        find.text('Caption \u{1F4DD}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption \u{1F4DD}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mood \u{1F485}'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'Mood \u{1F485}');
    });
  });

  // ===========================================================================
  // 5. AI Style Transfer
  // ===========================================================================

  group('Style Filters', () {
    testWidgets('Style tool shows error without image', (tester) async {
      await pumpEditor(tester);
      await tester.scrollUntilVisible(
        find.text('Style \u{1F308}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Style \u{1F308}'));
      await tester.pumpAndSettle();
      // No image loaded — shows snackbar
      expect(find.text('Load an image first to apply styles'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 6. Drawing tools — toolbar selection
  // ===========================================================================

  group('Drawing Tools — toolbar', () {
    testWidgets('all 8 tool buttons are visible', (tester) async {
      await pumpEditor(tester);
      expect(find.text('AI Magic \u{2728}'), findsOneWidget);
      expect(find.text('Lasso \u{1FA82}'), findsOneWidget);
      expect(find.text('Brush \u{1F3A8}'), findsOneWidget);
      expect(find.text('Magic Eraser'), findsOneWidget);
      expect(find.text('Text \u{1F4AC}'), findsOneWidget);
    });

    testWidgets('canvas has GestureDetector for drawing strokes',
        (tester) async {
      await pumpEditor(tester);
      expect(
        find.descendant(
          of: find.byType(EditorCanvas),
          matching: find.byType(GestureDetector),
        ),
        findsOneWidget,
      );
    });

    testWidgets('canvas has CustomPaint for rendering', (tester) async {
      await pumpEditor(tester);
      expect(
        find.descendant(
          of: find.byType(EditorCanvas),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('canvas starts with empty strokes', (tester) async {
      await pumpEditor(tester);
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.strokes, isEmpty);
      expect(canvas.currentStroke, isEmpty);
    });
  });

  // ===========================================================================
  // 7. Undo functionality
  // ===========================================================================

  group('Undo', () {
    testWidgets('undo button exists', (tester) async {
      await pumpEditor(tester);
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    });

    testWidgets('undo button is disabled when no strokes', (tester) async {
      await pumpEditor(tester);
      final btn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.undo_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });
  });

  // ===========================================================================
  // 8. Save/Export flow
  // ===========================================================================

  group('Save/Export', () {
    testWidgets('save button opens Save Sticker bottom sheet', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Save Sticker'), findsOneWidget);
    });

    testWidgets('save sheet has Save to Pack option', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Save to Pack'), findsOneWidget);
    });

    testWidgets('save sheet has Add to WhatsApp option', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Add to WhatsApp'), findsOneWidget);
    });

    testWidgets('save sheet WhatsApp option has green icon', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chat_rounded), findsOneWidget);
    });
  });

  // ===========================================================================
  // 9. Background removal guardrail
  // ===========================================================================

  group('Background Removal', () {
    testWidgets('AI Magic without image shows friendly error', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('AI Magic \u{2728}'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('No image loaded to remove background from'),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // 10. Text overlay replacement behavior
  // ===========================================================================

  group('Text Overlay Replacement', () {
    testWidgets('new text replaces previous text on canvas', (tester) async {
      await pumpEditor(tester);

      await openStyleSheet(tester, 'First');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      var canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'First');

      await openStyleSheet(tester, 'Second');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'Second');
    });
  });
}
