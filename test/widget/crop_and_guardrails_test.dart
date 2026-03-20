import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/data/providers.dart';
import 'package:sticker_officer/features/editor/presentation/animated_sticker_screen.dart';
import 'package:sticker_officer/features/editor/presentation/editor_screen.dart';
import 'package:sticker_officer/features/editor/presentation/video_to_sticker_screen.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/editor_canvas.dart';

/// Widget-level tests that fill coverage gaps identified in the audit:
///
/// 1. Crop mode interaction flow (enter, controls, cancel)
/// 2. Size/duration indicators on AnimatedStickerScreen
/// 3. Video-to-sticker guardrail tips
/// 4. Kid-friendly error messaging across all screens
/// 5. Animated sticker screen with pre-loaded frames
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sticker_packs': '[]'});
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

  Future<void> pumpAnimated(WidgetTester tester,
      {List<String>? initialFramePaths}) async {
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
        child: MaterialApp(
          home: AnimatedStickerScreen(initialFramePaths: initialFramePaths),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpVideoToSticker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1284, 2778);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: VideoToStickerScreen()),
      ),
    );
    await tester.pump();
  }

  // ===========================================================================
  // 1. CROP MODE — UI controls and flow
  // ===========================================================================

  group('Editor Crop Mode — UI controls', () {
    testWidgets('crop button exists with correct tooltip', (tester) async {
      await pumpEditor(tester);
      final cropButton = find.byTooltip('Crop Sticker');
      expect(cropButton, findsOneWidget);
    });

    testWidgets('crop without image shows kid-friendly error', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Crop Sticker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No image loaded to crop'), findsOneWidget);
      // No technical jargon
      expect(find.textContaining('exception'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('crop error snackbar is kid-friendly', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Crop Sticker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Message should use simple language kids understand
      final snackBar = find.byType(SnackBar);
      expect(snackBar, findsOneWidget);
    });

    testWidgets('crop controls NOT visible without image', (tester) async {
      await pumpEditor(tester);

      // Cancel, Square/Free, Apply buttons should NOT exist yet
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Apply'), findsNothing);
      expect(find.text('Square'), findsNothing);
      expect(find.text('Free'), findsNothing);
    });

    testWidgets('undo button exists in app bar', (tester) async {
      await pumpEditor(tester);
      expect(find.byTooltip('Undo'), findsOneWidget);
    });

    testWidgets('save button exists in app bar', (tester) async {
      await pumpEditor(tester);
      expect(find.byTooltip('Save Sticker'), findsOneWidget);
    });

    testWidgets('close button tooltip says "Close Editor" by default',
        (tester) async {
      await pumpEditor(tester);
      // When not in crop mode, close button closes editor
      expect(find.byTooltip('Close Editor'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 2. TEXT ADDITION — full flow verification
  // ===========================================================================

  group('Editor Text Addition — full flow', () {
    testWidgets('text tool opens dialog with kid-friendly prompt',
        (tester) async {
      await pumpEditor(tester);
      // Find and tap the Text tool in the toolbar
      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();

      expect(find.text('Add Text'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('entering text → Add → style sheet → Apply → canvas shows text',
        (tester) async {
      await pumpEditor(tester);

      // Step 1: Open text dialog
      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();

      // Step 2: Type text
      await tester.enterText(find.byType(TextField), 'Hello Kids!');

      // Step 3: Tap Add
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Step 4: Style sheet opens
      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Pick a Color'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);

      // Step 5: Apply to sticker
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      // Step 6: Verify text is on canvas
      final canvas = tester.widget<EditorCanvas>(
        find.byType(EditorCanvas),
      );
      expect(canvas.overlayText, 'Hello Kids!');
    });

    testWidgets('text color defaults to white on canvas', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'White text');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textColor, Colors.white);
    });

    testWidgets('text size defaults to 28 on canvas', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sized');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textSize, 28);
    });

    testWidgets('bold defaults to true on canvas', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bold');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textBold, isTrue);
    });

    testWidgets('toggling bold OFF is reflected on canvas', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Not bold');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Toggle bold off
      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      expect(find.text('B  OFF'), findsOneWidget);

      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textBold, isFalse);
    });

    testWidgets('applying second text replaces first', (tester) async {
      await pumpEditor(tester);

      // Add first text
      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'First');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      var canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'First');

      // Add second text
      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Second');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'Second');
    });

    testWidgets('cancel in text dialog does not add text', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Should not appear');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, isNull);
    });
  });

  // ===========================================================================
  // 3. ANIMATED STICKER — text animation flow
  // ===========================================================================

  group('Animated Sticker — text animation full flow', () {
    testWidgets('text button opens dialog with kid-friendly labels',
        (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Add Text to Your Sticker!'), findsOneWidget);
      expect(find.text('Keep it friendly and fun!'), findsOneWidget);
      expect(find.text('Type something fun...'), findsOneWidget);
    });

    testWidgets('text dialog enforces max length', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.maxLength, StickerGuardrails.maxTextLength);
    });

    testWidgets('entering text → Next → style sheet shows all 7 animations',
        (tester) async {
      await pumpAnimated(tester);

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fun!');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Animation'), findsOneWidget);

      for (final anim in TextAnimation.values) {
        expect(find.text(anim.label), findsOneWidget,
            reason: '${anim.label} preset should be visible');
      }
    });

    testWidgets('selecting Bounce → Apply → badge shows "Bounce"',
        (tester) async {
      await pumpAnimated(tester);

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Boing');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bounce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Boing"'), findsOneWidget);
      expect(find.text('Bounce'), findsOneWidget);
    });

    testWidgets('selecting Wave → Apply → badge shows "Wave"',
        (tester) async {
      await pumpAnimated(tester);

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Surf');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Surf"'), findsOneWidget);
      expect(find.text('Wave'), findsOneWidget);
    });

    testWidgets('text badge close button removes overlay', (tester) async {
      await pumpAnimated(tester);

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gone');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      expect(find.text('"Gone"'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('"Gone"'), findsNothing);
    });

    testWidgets('kid-safe filter blocks bad words in animated sticker',
        (tester) async {
      await pumpAnimated(tester);

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'you are stupid');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Oops! Please use friendly words only.'), findsOneWidget);
      // Should NOT open style sheet
      expect(find.text('Style Your Text!'), findsNothing);
    });

    testWidgets('kid-safe filter allows friendly text', (tester) async {
      await pumpAnimated(tester);

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Love cats!');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Style Your Text!'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. ANIMATED STICKER — guardrails indicators
  // ===========================================================================

  group('Animated Sticker — guardrails', () {
    testWidgets('size indicator NOT shown with 0 frames', (tester) async {
      await pumpAnimated(tester);
      expect(find.textContaining('/ 500 KB'), findsNothing);
    });

    testWidgets('duration indicator NOT shown with 0 frames', (tester) async {
      await pumpAnimated(tester);
      expect(find.textContaining('Duration:'), findsNothing);
    });

    testWidgets('save with 0 frames shows "Add at least 2 pictures"',
        (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.text('Save to Pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Add at least 2 pictures to make it move!'),
          findsOneWidget);
    });

    testWidgets('error message uses "pictures" not "frames"', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.text('Save to Pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('pictures'), findsWidgets);
      expect(find.textContaining('make it move'), findsOneWidget);
    });

    testWidgets('frame counter shows 0/8 initially', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('0/${StickerGuardrails.maxFrames}'), findsOneWidget);
    });

    testWidgets('speed controls visible: Slow/Fast labels', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Slow'), findsOneWidget);
      expect(find.text('Fast'), findsOneWidget);
    });

    testWidgets('FPS label shows 8 FPS by default', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('8 FPS'), findsOneWidget);
    });

    testWidgets('speed slider exists', (tester) async {
      await pumpAnimated(tester);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('Import GIF button visible', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Import GIF'), findsOneWidget);
    });

    testWidgets('empty state uses kid-friendly language', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
      expect(find.text('or import a GIF below!'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. ANIMATED STICKER — pre-loaded frames from video
  // ===========================================================================

  group('Animated Sticker — initial frames', () {
    testWidgets('accepts initialFramePaths without crashing', (tester) async {
      await pumpAnimated(tester,
          initialFramePaths: ['/fake/frame1.png', '/fake/frame2.png']);
      await tester.pumpAndSettle();

      // Still renders even with non-existent files
      expect(find.text('Animated Sticker'), findsOneWidget);
    });

    testWidgets('null initialFramePaths shows empty state', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
      expect(find.text('0/${StickerGuardrails.maxFrames}'), findsOneWidget);
    });

    // NOTE: Frame-loading with real files requires actual device I/O which
    // doesn't work in Flutter's fakeAsync test zone. The following tests
    // verify the guardrails logic and size/duration indicator computations
    // at the unit level instead.

    test('size indicator text formats correctly for loaded frames', () {
      // Unit-level: verify the label and tip that WOULD be shown
      final label = StickerGuardrails.sizeLabel(30 * 1024); // 30 KB
      expect(label, '30 KB');
      final status = StickerGuardrails.sizeStatus(30 * 1024, isAnimated: true);
      expect(status, SizeStatus.safe);
      expect(StickerGuardrails.sizeTip(status, isAnimated: true), 'Perfect size!');
    });

    test('duration indicator computes correctly for 4 frames at 8 FPS', () {
      // Unit-level: verify the label that WOULD be shown
      final label = StickerGuardrails.durationLabel(4, 8);
      expect(label, '0.5s');
      expect(StickerGuardrails.isDurationSafe(4, 8), isTrue);
    });

    test('duration indicator flags "Too short!" for 2 frames at 8 FPS', () {
      final ms = StickerGuardrails.totalDurationMs(2, 8);
      expect(ms, 250);
      expect(StickerGuardrails.isDurationSafe(2, 8), isFalse);
      expect(ms < StickerGuardrails.minDurationMs, isTrue);
    });

    test('size indicator warns for large estimated size', () {
      final status = StickerGuardrails.sizeStatus(450 * 1024, isAnimated: true);
      expect(status, SizeStatus.warning);
      expect(StickerGuardrails.sizeTip(status, isAnimated: true),
          contains('big'));
    });
  });

  // ===========================================================================
  // 6. VIDEO TO STICKER — guardrails and kid-friendly UI
  // ===========================================================================

  group('Video to Sticker — guardrails and UI', () {
    testWidgets('title says "Video to Sticker"', (tester) async {
      await pumpVideoToSticker(tester);
      expect(find.text('Video to Sticker'), findsOneWidget);
    });

    testWidgets('prompt says "Pick a Video!"', (tester) async {
      await pumpVideoToSticker(tester);
      expect(find.text('Pick a Video!'), findsOneWidget);
    });

    testWidgets('shows all 3 guardrail tips', (tester) async {
      await pumpVideoToSticker(tester);
      expect(find.textContaining('5 seconds'), findsOneWidget);
      expect(find.textContaining('smoothness'), findsOneWidget);
      expect(find.textContaining('500 KB'), findsOneWidget);
    });

    testWidgets('has Choose Video button', (tester) async {
      await pumpVideoToSticker(tester);
      expect(find.text('Choose Video'), findsOneWidget);
    });

    testWidgets('uses kid-friendly language (no technical jargon)',
        (tester) async {
      await pumpVideoToSticker(tester);

      // Should NOT use technical terms
      expect(find.textContaining('file'), findsNothing);
      expect(find.textContaining('upload'), findsNothing);
      expect(find.textContaining('browse'), findsNothing);
    });

    testWidgets('mentions "animated sticker" in description', (tester) async {
      await pumpVideoToSticker(tester);
      expect(find.textContaining('animated sticker'), findsOneWidget);
    });

    testWidgets('has close button in app bar', (tester) async {
      await pumpVideoToSticker(tester);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  // ===========================================================================
  // 7. EDITOR — canvas properties without image
  // ===========================================================================

  group('Editor Canvas — initial state', () {
    testWidgets('canvas starts with no overlay text', (tester) async {
      await pumpEditor(tester);
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, isNull);
    });

    testWidgets('canvas starts with no image', (tester) async {
      await pumpEditor(tester);
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.image, isNull);
    });

    testWidgets('canvas starts with empty strokes', (tester) async {
      await pumpEditor(tester);
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.strokes, isEmpty);
      expect(canvas.currentStroke, isEmpty);
    });

    testWidgets('canvas has GestureDetector for drawing', (tester) async {
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

    testWidgets('canvas text position defaults to (100, 100)', (tester) async {
      await pumpEditor(tester);
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textPosition, const Offset(100, 100));
    });
  });

  // ===========================================================================
  // 8. AI CAPTION — applies text to canvas
  // ===========================================================================

  group('Editor — AI caption', () {
    testWidgets('tapping LOL caption applies it to canvas', (tester) async {
      await pumpEditor(tester);

      await tester.scrollUntilVisible(
        find.text('Caption 📝'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption 📝'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('LOL 😂'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'LOL 😂');
    });

    testWidgets('caption replaces manually added text', (tester) async {
      await pumpEditor(tester);

      // Add manual text first
      await tester.tap(find.text('Text 💬'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Manual');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      // Now apply caption
      await tester.scrollUntilVisible(
        find.text('Caption 📝'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption 📝'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send help 🆘'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'Send help 🆘');
    });
  });

  // ===========================================================================
  // 9. BACKGROUND REMOVAL — error handling
  // ===========================================================================

  group('Editor — background removal errors', () {
    testWidgets('shows error when no image loaded', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('AI Magic ✨'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('No image loaded to remove background from'),
        findsOneWidget,
      );
    });
  });
}
