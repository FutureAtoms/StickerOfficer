import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sticker_officer/app.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/data/providers.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:sticker_officer/features/editor/presentation/widgets/editor_toolbar.dart';

/// Integration tests that run on a real device/emulator to verify:
/// 1. Image cropping flow & guardrails
/// 2. Text addition with styling
/// 3. Text animation in animated stickers
/// 4. Animated sticker GIF controls & guardrails
/// 5. Kid-safe text filter
/// 6. Size/duration guardrails
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  /// Suppress RenderFlex overflow errors that can occur on various simulator
  /// screen sizes — these are cosmetic warnings, not logic failures.
  void suppressOverflowErrors() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.toString();
      if (msg.contains('overflowed') || msg.contains('RenderFlex')) return;
      (original ?? FlutterError.presentError)(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    suppressOverflowErrors();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const StickerOfficerApp(),
      ),
    );
    // Use pump with explicit duration instead of pumpAndSettle because the
    // feed screen has persistent shimmer/animation widgets that never settle.
    await tester.pump(const Duration(seconds: 2));
  }

  // ===========================================================================
  // 1. Static Editor — render, crop guardrail, text addition
  // ===========================================================================

  group('Static Editor', () {
    testWidgets('editor renders with canvas and toolbar', (tester) async {
      await pumpApp(tester);

      // Navigate to editor: tap Create (+) in bottom nav
      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();

      // Tap "From Photo" in the create sheet
      await tester.tap(find.text('From Photo'));
      await tester.pumpAndSettle();

      // Editor should be visible
      expect(find.text('Sticker Editor'), findsOneWidget);
      expect(find.byType(EditorCanvas), findsOneWidget);
      expect(find.byType(EditorToolbar), findsOneWidget);
    });

    testWidgets('crop without image shows friendly guardrail', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Photo'));
      await tester.pumpAndSettle();

      // Tap crop icon
      await tester.tap(find.byIcon(Icons.crop_rounded));
      await tester.pumpAndSettle();

      expect(find.text('No image loaded to crop'), findsOneWidget);
    });

    testWidgets('text addition: dialog → style sheet → canvas overlay',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Photo'));
      await tester.pumpAndSettle();

      // Tap Text tool in toolbar
      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();

      // Add Text dialog appears
      expect(find.text('Add Text'), findsOneWidget);

      // Type text
      await tester.enterText(find.byType(TextField), 'Hello Kids!');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Style sheet opens
      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Pick a Color'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('B  ON'), findsOneWidget);

      // Apply text
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      // Text should be on the canvas
      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'Hello Kids!');
      expect(canvas.textColor, Colors.white);
      expect(canvas.textBold, isTrue);
    });

    testWidgets('bold toggle works in style sheet', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Text \u{1F4AC}'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bold test');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Toggle bold off
      await tester.tap(find.text('B  ON'));
      await tester.pumpAndSettle();
      expect(find.text('B  OFF'), findsOneWidget);

      // Apply
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.textBold, isFalse);
    });

    testWidgets('AI caption applies to canvas', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Photo'));
      await tester.pumpAndSettle();

      // Scroll toolbar to Caption button
      await tester.scrollUntilVisible(
        find.text('Caption \u{1F4DD}'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Caption \u{1F4DD}'));
      await tester.pumpAndSettle();

      // Tap a caption
      await tester.tap(find.text('LOL \u{1F602}'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<EditorCanvas>(find.byType(EditorCanvas));
      expect(canvas.overlayText, 'LOL \u{1F602}');
    });

    testWidgets('save button opens save sheet', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_rounded));
      // Use pump instead of pumpAndSettle — bottom sheet animation can
      // cause pumpAndSettle to time out on some simulators.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Save Sticker'), findsOneWidget);
      expect(find.text('Save to Pack'), findsOneWidget);
      expect(find.text('Add to WhatsApp'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 2. Animated Sticker — render, text animation, guardrails
  // ===========================================================================

  group('Animated Sticker', () {
    testWidgets('animated sticker screen renders with kid-friendly UI',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Animated Sticker'), findsOneWidget);
      expect(find.text('Tap to add pictures!'), findsOneWidget);
      expect(
        find.text('Up to ${StickerGuardrails.maxFrames} images'),
        findsOneWidget,
      );
      expect(find.text('or import a GIF below!'), findsOneWidget);
      expect(find.text('Import GIF'), findsOneWidget);
      expect(find.text('Save to Pack'), findsOneWidget);
      expect(find.text('0/${StickerGuardrails.maxFrames}'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('8 FPS'), findsOneWidget);
    });

    testWidgets('save with 0 frames shows guardrail error', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      // Try to save with 0 frames
      await tester.tap(find.text('Save to Pack'));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('Add at least 2 pictures to make it move!'),
        findsOneWidget,
      );
    });

    testWidgets('text overlay dialog with kid-safe features', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      // Tap text button in app bar
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pump(const Duration(seconds: 1));

      // Dialog appears with kid-friendly hints
      expect(find.text('Add Text to Your Sticker!'), findsOneWidget);
      expect(find.text('Type something fun...'), findsOneWidget);
      expect(find.text('Keep it friendly and fun!'), findsOneWidget);

      // Check max length
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLength, StickerGuardrails.maxTextLength);
    });

    testWidgets('kid-safe filter blocks inappropriate words', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pump(const Duration(seconds: 1));

      // Type blocked word
      await tester.enterText(find.byType(TextField), 'you are stupid');
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(seconds: 1));

      // Should show friendly error, NOT open style sheet
      expect(
        find.text('Oops! Please use friendly words only.'),
        findsOneWidget,
      );
      expect(find.text('Style Your Text!'), findsNothing);
    });

    testWidgets('text animation style sheet shows all 7 presets',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), 'Bounce test');
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(seconds: 1));

      // Style sheet with animation presets
      expect(find.text('Style Your Text!'), findsOneWidget);
      expect(find.text('Animation'), findsOneWidget);
      for (final anim in TextAnimation.values) {
        expect(find.text(anim.label), findsOneWidget);
      }
    });

    testWidgets('applying text with Bounce shows badge', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), 'Fun!');
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(seconds: 1));

      // Select Bounce — use pump to avoid animation settle timeout
      await tester.tap(find.text('Bounce'));
      await tester.pump(const Duration(milliseconds: 500));

      // Apply
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pump(const Duration(seconds: 1));

      // Badge shows text and animation name
      expect(find.text('"Fun!"'), findsOneWidget);
      expect(find.text('Bounce'), findsOneWidget);
    });

    testWidgets('text badge can be removed', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Animated Sticker'));
      await tester.pump(const Duration(seconds: 2));

      // Add text
      await tester.tap(find.byIcon(Icons.text_fields_outlined));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), 'Remove me');
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Add to Sticker!'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('"Remove me"'), findsOneWidget);

      // Remove via close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('"Remove me"'), findsNothing);
    });
  });

  // ===========================================================================
  // 3. Home feed & navigation
  // ===========================================================================

  group('App navigation', () {
    testWidgets('home feed shows sticker packs', (tester) async {
      await pumpApp(tester);

      expect(find.text('StickerOfficer'), findsOneWidget);
      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Challenges'), findsOneWidget);
    });

    testWidgets('bottom nav has all tabs', (tester) async {
      await pumpApp(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('My Packs'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('create sheet shows all options including From Video',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Create a Sticker'), findsOneWidget);
      expect(find.text('From Photo'), findsOneWidget);
      expect(find.text('AI Generate'), findsOneWidget);
      expect(find.text('Animated Sticker'), findsOneWidget);
      expect(find.text('From Video'), findsOneWidget);
      expect(find.text('From Template'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. Video to Sticker — navigation and picker state
  // ===========================================================================

  group('Video to Sticker', () {
    testWidgets('navigating to video-to-sticker shows picker UI',
        (tester) async {
      await pumpApp(tester);

      // Tap Create (+) in bottom nav
      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));

      // Tap "From Video"
      await tester.tap(find.text('From Video'));
      await tester.pump(const Duration(seconds: 2));

      // Video to Sticker screen should be visible
      expect(find.text('Video to Sticker'), findsOneWidget);
      expect(find.text('Pick a Video!'), findsOneWidget);
      expect(find.text('Choose Video'), findsOneWidget);
    });

    testWidgets('video-to-sticker shows guardrail tips', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('From Video'));
      await tester.pump(const Duration(seconds: 2));

      // Guardrail tips
      expect(find.text('Max 5 seconds'), findsOneWidget);
      expect(find.text('Extracts up to 8 frames'), findsOneWidget);
      expect(find.text('Keeps it under 500 KB'), findsOneWidget);
    });

    testWidgets('video-to-sticker shows kid-friendly description',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('From Video'));
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.textContaining("we'll turn it into an animated sticker"),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // 5. WhatsApp Export — UI presence
  // ===========================================================================

  group('WhatsApp Export', () {
    testWidgets('editor save sheet shows Add to WhatsApp option',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('From Photo'));
      await tester.pump(const Duration(seconds: 2));

      // Tap save button
      await tester.tap(find.byIcon(Icons.check_rounded));
      // Use pump instead of pumpAndSettle — bottom sheet animation can
      // cause pumpAndSettle to time out.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Save Sticker'), findsOneWidget);
      expect(find.text('Save to Pack'), findsOneWidget);
      expect(find.text('Add to WhatsApp'), findsOneWidget);
    });

    testWidgets('My Packs screen is accessible from bottom nav',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('My Packs'));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('My Packs'), findsWidgets);
    });
  });
}
