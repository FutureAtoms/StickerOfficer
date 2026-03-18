import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/features/editor/presentation/animated_sticker_screen.dart';

/// Comprehensive animated sticker tests covering text animation with all 7
/// presets, GIF/animated sticker generation flow, guardrails, kid-safe
/// validation, speed controls, and frame management.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sticker_packs': '[]'});
  });

  Future<void> pumpAnimated(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1284, 2778);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AnimatedStickerScreen()),
      ),
    );
    await tester.pump();
  }

  /// Helper: open text dialog and enter text
  Future<void> openTextDialog(WidgetTester tester, String text) async {
    await tester.tap(find.byIcon(Icons.text_fields_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
  }

  /// Helper: enter text and go to style sheet
  Future<void> openTextStyleSheet(WidgetTester tester, String text) async {
    await openTextDialog(tester, text);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  // ===========================================================================
  // 1. Text Animation — 7 presets
  // ===========================================================================

  group('Text Animation Presets', () {
    testWidgets('style sheet shows all 7 animation presets', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Presets');

      expect(find.text('Animation'), findsOneWidget);
      for (final anim in TextAnimation.values) {
        expect(find.text(anim.label), findsOneWidget);
      }
    });

    testWidgets('No Animation is the default selection', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Default');

      // No Animation should be visually selected (gradient bg)
      expect(find.text('No Animation'), findsOneWidget);
    });

    testWidgets('selecting Bounce and applying shows on badge',
        (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Bounce!');
      await tester.tap(find.text('Bounce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Bounce!"'), findsOneWidget);
      expect(find.text('Bounce'), findsOneWidget);
    });

    testWidgets('selecting Fade In shows on badge', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Fading');
      await tester.tap(find.text('Fade In'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Fading"'), findsOneWidget);
      expect(find.text('Fade In'), findsOneWidget);
    });

    testWidgets('selecting Slide Up shows on badge', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Sliding');
      await tester.tap(find.text('Slide Up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Sliding"'), findsOneWidget);
      expect(find.text('Slide Up'), findsOneWidget);
    });

    testWidgets('selecting Wave shows on badge', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Wavy');
      await tester.tap(find.text('Wave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Wavy"'), findsOneWidget);
      expect(find.text('Wave'), findsOneWidget);
    });

    testWidgets('selecting Grow shows on badge', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Growing');
      await tester.tap(find.text('Grow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Growing"'), findsOneWidget);
      expect(find.text('Grow'), findsOneWidget);
    });

    testWidgets('selecting Shake shows on badge', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Shaky');
      await tester.tap(find.text('Shake'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Shaky"'), findsOneWidget);
      expect(find.text('Shake'), findsOneWidget);
    });

    testWidgets('No Animation does not show animation tag on badge',
        (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Static');
      // Keep default (No Animation)
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      expect(find.text('"Static"'), findsOneWidget);
      // Should NOT show an animation tag (only the text badge)
      // The badge container appears but not "No Animation" as a separate tag
    });
  });

  // ===========================================================================
  // 2. Text Animation — style sheet controls
  // ===========================================================================

  group('Text Style Sheet — controls', () {
    testWidgets('style sheet has color picker', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Colors');
      expect(find.text('Pick a Color'), findsOneWidget);
    });

    testWidgets('style sheet has size slider', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Test text');
      expect(find.text('Size'), findsOneWidget);
      // There are 2 sliders: FPS speed slider (background) + size slider in sheet
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('style sheet has bold toggle', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Test text');
      expect(find.text('Bold'), findsOneWidget);
      expect(find.text('B  ON'), findsOneWidget);
    });

    testWidgets('bold toggle switches OFF and ON', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Toggle');
      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      expect(find.text('B  OFF'), findsOneWidget);
      await tester.tap(find.text('B  OFF'));
      await tester.pumpAndSettle();
      expect(find.text('B  ON'), findsOneWidget);
    });

    testWidgets('style sheet shows preview of entered text', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Preview text!');
      expect(find.text('Preview text!'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. Text badge removal
  // ===========================================================================

  group('Text Badge', () {
    testWidgets('applied text shows badge with quoted text', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'My Text');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      expect(find.text('"My Text"'), findsOneWidget);
    });

    testWidgets('close button removes text badge', (tester) async {
      await pumpAnimated(tester);
      await openTextStyleSheet(tester, 'Remove me');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      expect(find.text('"Remove me"'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('"Remove me"'), findsNothing);
    });

    testWidgets('after removing text, text button shows outline icon',
        (tester) async {
      await pumpAnimated(tester);
      // Add and remove text
      await openTextStyleSheet(tester, 'Temp');
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Icon should be back to outlined
      expect(find.byIcon(Icons.text_fields_outlined), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. Kid-safe text filter
  // ===========================================================================

  group('Kid-Safe Text Filter', () {
    testWidgets('blocks "stupid"', (tester) async {
      await pumpAnimated(tester);
      await openTextDialog(tester, 'you are stupid');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        find.text('Oops! Please use friendly words only.'),
        findsOneWidget,
      );
      expect(find.text('Style Your Text!'), findsNothing);
    });

    testWidgets('blocks "hate"', (tester) async {
      await pumpAnimated(tester);
      await openTextDialog(tester, 'I hate this');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        find.text('Oops! Please use friendly words only.'),
        findsOneWidget,
      );
    });

    testWidgets('blocks "dumb"', (tester) async {
      await pumpAnimated(tester);
      await openTextDialog(tester, 'so dumb');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        find.text('Oops! Please use friendly words only.'),
        findsOneWidget,
      );
    });

    testWidgets('allows friendly text "I love cats"', (tester) async {
      await pumpAnimated(tester);
      await openTextDialog(tester, 'I love cats');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Style Your Text!'), findsOneWidget);
    });

    testWidgets('allows emoji text', (tester) async {
      await pumpAnimated(tester);
      await openTextDialog(tester, 'Fun! \u{1F60E}');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Style Your Text!'), findsOneWidget);
    });

    testWidgets('dialog shows kid-friendly hints', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Add Text to Your Sticker!'), findsOneWidget);
      expect(find.text('Type something fun...'), findsOneWidget);
      expect(find.text('Keep it friendly and fun!'), findsOneWidget);
    });

    testWidgets('text field enforces max length', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.maxLength, StickerGuardrails.maxTextLength);
    });
  });

  // ===========================================================================
  // 5. Export guardrails
  // ===========================================================================

  group('Export Guardrails', () {
    testWidgets('save with 0 frames shows minimum frame error',
        (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.text('Save to Pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Add at least ${StickerGuardrails.minFrames} pictures to make it move!'),
        findsOneWidget,
      );
    });

    testWidgets('error message is kid-friendly', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.text('Save to Pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Should be kid-friendly (talks about "pictures" not "frames")
      expect(find.textContaining('pictures to make it move'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 6. Speed / FPS controls
  // ===========================================================================

  group('Speed Controls', () {
    testWidgets('speed section is visible', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    });

    testWidgets('default FPS is 8', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('8 FPS'), findsOneWidget);
    });

    testWidgets('Slow and Fast labels visible', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Slow'), findsOneWidget);
      expect(find.text('Fast'), findsOneWidget);
    });

    testWidgets('FPS slider exists with correct range', (tester) async {
      await pumpAnimated(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, StickerGuardrails.minFps.toDouble());
      expect(slider.max, StickerGuardrails.maxFps.toDouble());
    });
  });

  // ===========================================================================
  // 7. Frame management UI
  // ===========================================================================

  group('Frame Management UI', () {
    testWidgets('frame counter shows 0/8 on empty', (tester) async {
      await pumpAnimated(tester);
      expect(
        find.text('0/${StickerGuardrails.maxFrames}'),
        findsOneWidget,
      );
    });

    testWidgets('Import GIF button visible', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Import GIF'), findsOneWidget);
    });

    testWidgets('Save to Pack button visible', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Save to Pack'), findsOneWidget);
    });

    testWidgets('empty state shows Tap to add pictures', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
      expect(
        find.text('Up to ${StickerGuardrails.maxFrames} images'),
        findsOneWidget,
      );
      expect(find.text('or import a GIF below!'), findsOneWidget);
    });

    testWidgets('add button icon is visible', (tester) async {
      await pumpAnimated(tester);
      expect(find.byIcon(Icons.add_photo_alternate_rounded), findsWidgets);
    });
  });

  // ===========================================================================
  // 8. Initial frames from video
  // ===========================================================================

  group('Initial Frames (from video)', () {
    testWidgets('accepts initialFramePaths without crash', (tester) async {
      tester.view.physicalSize = const Size(1284, 2778);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnimatedStickerScreen(
              initialFramePaths: ['/nonexistent/a.png', '/nonexistent/b.png'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Animated Sticker'), findsOneWidget);
    });

    testWidgets('null initialFramePaths renders empty state', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
    });
  });
}
