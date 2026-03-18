import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/features/editor/presentation/video_to_sticker_screen.dart';

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
  // 1. Initial picker state
  // ===========================================================================

  group('VideoToStickerScreen — picker state', () {
    testWidgets('shows title', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Video to Sticker'), findsOneWidget);
    });

    testWidgets('shows pick video prompt', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Pick a Video!'), findsOneWidget);
    });

    testWidgets('shows Choose Video button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Choose Video'), findsOneWidget);
    });

    testWidgets('shows max duration tip', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Max 5 seconds'), findsOneWidget);
    });

    testWidgets('shows frame extraction tip', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Extracts up to 8 frames'), findsOneWidget);
    });

    testWidgets('shows size limit tip', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Keeps it under 500 KB'), findsOneWidget);
    });

    testWidgets('shows video icon', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    });

    testWidgets('shows kid-friendly description', (tester) async {
      await pumpScreen(tester);
      expect(
        find.textContaining("we'll turn it into an animated sticker"),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // 2. UI structure
  // ===========================================================================

  group('VideoToStickerScreen — UI structure', () {
    testWidgets('has close button in app bar', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('has video call icon on Choose Video button', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.video_call_rounded), findsOneWidget);
    });

    testWidgets('tips are in a container', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.byIcon(Icons.data_usage_rounded), findsOneWidget);
    });
  });
}
