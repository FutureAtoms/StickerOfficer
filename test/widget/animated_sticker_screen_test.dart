import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/features/editor/presentation/animated_sticker_screen.dart';

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

  // ===========================================================================
  // 1. Renders
  // ===========================================================================

  group('AnimatedStickerScreen — renders', () {
    testWidgets('shows title', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Animated Sticker'), findsOneWidget);
    });

    testWidgets('shows empty state prompt', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
    });

    testWidgets('shows frame limit hint', (tester) async {
      await pumpAnimated(tester);
      expect(
        find.text('Up to ${StickerGuardrails.maxFrames} images'),
        findsOneWidget,
      );
    });

    testWidgets('shows GIF import hint', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('or import a GIF below!'), findsOneWidget);
    });

    testWidgets('shows Import GIF button', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Import GIF'), findsOneWidget);
    });

    testWidgets('shows Save to Pack button', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Save to Pack'), findsOneWidget);
    });

    testWidgets('shows text overlay button', (tester) async {
      await pumpAnimated(tester);
      expect(find.byIcon(Icons.text_fields_outlined), findsOneWidget);
    });

    testWidgets('shows frame counter 0/8', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('0/${StickerGuardrails.maxFrames}'), findsOneWidget);
    });

    testWidgets('shows speed controls', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('8 FPS'), findsOneWidget);
      expect(find.text('Slow'), findsOneWidget);
      expect(find.text('Fast'), findsOneWidget);
    });

    testWidgets('has speed slider', (tester) async {
      await pumpAnimated(tester);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('play button not visible until frames added', (tester) async {
      await pumpAnimated(tester);
      // Play button only appears after frames are added
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsNothing);
    });
  });

  // ===========================================================================
  // 2. Text animation
  // ===========================================================================

  group('AnimatedStickerScreen — text animation', () {
    testWidgets('tapping text button opens dialog', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Add Text to Your Sticker!'), findsOneWidget);
    });

    testWidgets('dialog has max length counter', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.maxLength, StickerGuardrails.maxTextLength);
    });

    testWidgets('dialog shows kid-friendly hint', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Keep it friendly and fun!'), findsOneWidget);
      expect(find.text('Type something fun...'), findsOneWidget);
    });

    testWidgets('Cancel dismisses dialog', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Text to Your Sticker!'), findsNothing);
    });

    testWidgets('entering text and Next opens style sheet', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fun sticker!');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Animation'), findsOneWidget);
    });

    testWidgets('style sheet shows all 7 animation presets', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Test');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      for (final anim in TextAnimation.values) {
        expect(find.text(anim.label), findsOneWidget);
      }
    });

    testWidgets('Apply closes sheet and shows text badge', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yo!');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      expect(find.text('"Yo!"'), findsOneWidget);
    });

    testWidgets('text badge close removes overlay', (tester) async {
      await pumpAnimated(tester);
      // Add text
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gone');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();
      expect(find.text('"Gone"'), findsOneWidget);

      // Remove
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('"Gone"'), findsNothing);
    });

    testWidgets('selecting Bounce shows it on badge', (tester) async {
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

      // Badge shows animation name
      expect(find.text('Bounce'), findsOneWidget);
    });

    testWidgets('kid-safe filter blocks bad words', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'you are stupid');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        find.text('Oops! Please use friendly words only.'),
        findsOneWidget,
      );
      expect(find.text('Style Your Text!'), findsNothing);
    });

    testWidgets('kid-safe filter allows friendly text', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Love cats!');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Should open style sheet
      expect(find.text('Style Your Text!'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. Export guardrails
  // ===========================================================================

  group('AnimatedStickerScreen — export guardrails', () {
    testWidgets('Save with 0 frames shows error', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.text('Save to Pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Add at least'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. Initial frames from video-to-sticker
  // ===========================================================================

  group('AnimatedStickerScreen — initial frame paths', () {
    testWidgets('accepts initialFramePaths parameter without crash',
        (tester) async {
      tester.view.physicalSize = const Size(1284, 2778);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pass initial frame paths — files won't exist in test, but should
      // not crash. The screen gracefully skips non-existent files.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnimatedStickerScreen(
              initialFramePaths: ['/fake/path/frame1.png', '/fake/path/frame2.png'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen still renders correctly
      expect(find.text('Animated Sticker'), findsOneWidget);
      // Frame counter shows 0 since files don't exist
      expect(find.text('0/${StickerGuardrails.maxFrames}'), findsOneWidget);
    });

    testWidgets('null initialFramePaths shows empty state', (tester) async {
      await pumpAnimated(tester);

      // Should show the empty state
      expect(find.text('Tap to add pictures!'), findsOneWidget);
      expect(find.text('0/${StickerGuardrails.maxFrames}'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. Kid-friendly UX
  // ===========================================================================

  group('AnimatedStickerScreen — kid-friendly UX', () {
    testWidgets('uses kid-friendly empty state language', (tester) async {
      await pumpAnimated(tester);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
      expect(find.text('or import a GIF below!'), findsOneWidget);
    });

    testWidgets('error messages are friendly', (tester) async {
      await pumpAnimated(tester);
      await tester.tap(find.text('Save to Pack'));
      await tester.pump(const Duration(milliseconds: 500));
      // Should say "Add at least 2 pictures to make it move!"
      expect(
        find.text('Add at least 2 pictures to make it move!'),
        findsOneWidget,
      );
    });
  });
}
