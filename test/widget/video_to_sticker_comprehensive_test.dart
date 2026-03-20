import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/features/editor/presentation/video_to_sticker_screen.dart';

/// Comprehensive video-to-sticker tests covering the picker state, guardrail
/// tips, kid-friendly UI, and all UI elements. Video file picking and frame
/// extraction require a real device (covered by integration tests).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sticker_packs': '[]'});
  });

  Future<void> pumpScreen(WidgetTester tester) async {
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
  // 1. Picker state — all elements
  // ===========================================================================

  group('Picker State', () {
    testWidgets('shows title "Video to Sticker"', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Video to Sticker'), findsOneWidget);
    });

    testWidgets('shows "Pick a Video!" heading', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Pick a Video!'), findsOneWidget);
    });

    testWidgets('shows Choose Video button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Choose Video'), findsOneWidget);
    });

    testWidgets('Choose Video button has video_call icon', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.video_call_rounded), findsOneWidget);
    });

    testWidgets('shows kid-friendly description', (tester) async {
      await pumpScreen(tester);
      expect(
        find.textContaining("we'll turn your favorite moment into a smooth animated sticker"),
        findsOneWidget,
      );
    });

    testWidgets('shows large video icon', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    });
  });

  // ===========================================================================
  // 2. Guardrail tips
  // ===========================================================================

  group('Guardrail Tips', () {
    testWidgets('shows max duration tip (5 seconds)', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Select up to 5 seconds'), findsOneWidget);
    });

    testWidgets('shows quality tip', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Adjust quality vs. smoothness'), findsOneWidget);
    });

    testWidgets('shows size limit tip (500 KB)', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Keeps it under 500 KB'), findsOneWidget);
    });

    testWidgets('tip icons are visible', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byIcon(Icons.data_usage_rounded), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. UI Structure
  // ===========================================================================

  group('UI Structure', () {
    testWidgets('has close button in app bar', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('close button is leading widget', (tester) async {
      await pumpScreen(tester);
      // The close icon is in the AppBar leading position
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.leading, isNotNull);
    });

    testWidgets('title is centered', (tester) async {
      await pumpScreen(tester);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isTrue);
    });

    testWidgets('content is centered when no video loaded', (tester) async {
      await pumpScreen(tester);
      // Should show the centered pick state
      expect(find.byType(Center), findsWidgets);
    });
  });

  // ===========================================================================
  // 4. Kid-friendly language
  // ===========================================================================

  group('Kid-Friendly Language', () {
    testWidgets('uses fun, encouraging language', (tester) async {
      await pumpScreen(tester);
      // Should say "Pick a Video!" not "Select video file"
      expect(find.text('Pick a Video!'), findsOneWidget);
      // Should say "Choose Video" not "Browse files"
      expect(find.text('Choose Video'), findsOneWidget);
    });

    testWidgets('no technical jargon visible', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('file'), findsNothing);
      expect(find.textContaining('upload'), findsNothing);
      expect(find.textContaining('browse'), findsNothing);
    });

    testWidgets('description mentions "animated sticker" for kids',
        (tester) async {
      await pumpScreen(tester);
      expect(
        find.textContaining('animated sticker'),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // 5. Guardrail constants validation
  // ===========================================================================

  group('Guardrail Constants', () {
    testWidgets('max duration shown as 5 seconds', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('5'), findsWidgets);
    });

    testWidgets('quality tip mentions smoothness', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('smoothness'), findsWidgets);
    });

    testWidgets('size limit shown as 500', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('500'), findsWidgets);
    });
  });
}
