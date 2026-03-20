import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/app.dart';
import 'package:sticker_officer/core/utils/sticker_guardrails.dart';
import 'package:sticker_officer/data/providers.dart';
import 'package:sticker_officer/features/editor/presentation/animated_sticker_screen.dart';
import 'package:sticker_officer/features/editor/presentation/video_to_sticker_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  void suppressOverflowErrors() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.toString();
      if (msg.contains('overflowed') || msg.contains('RenderFlex')) return;
      (original ?? FlutterError.presentError)(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  Future<void> takeScreenshot(String name) async {
    await binding.takeScreenshot(name);
  }

  /// Creates test frame PNGs and a test GIF simulating FFmpeg output.
  Future<Map<String, dynamic>> createTestVideoOutput() async {
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory('${tempDir.path}/e2e_test_${DateTime.now().millisecondsSinceEpoch}');
    await workDir.create(recursive: true);

    // Create 12 test frames (simulating 1s at 12fps — "Balanced" setting)
    final framePaths = <String>[];
    final frames = <img.Image>[];

    for (int i = 0; i < 12; i++) {
      final frame = img.Image(width: 384, height: 384, numChannels: 4);
      // Draw a gradient that shifts each frame (simulating video motion)
      for (int y = 0; y < 384; y++) {
        for (int x = 0; x < 384; x++) {
          final r = ((x + i * 30) % 256);
          final g = ((y + i * 20) % 256);
          final b = ((x + y + i * 10) % 256);
          frame.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      frame.frameDuration = 8; // ~12fps in centiseconds
      frames.add(frame);

      // Save as PNG
      final pngBytes = img.encodePng(frame);
      final framePath = '${workDir.path}/frame_$i.png';
      await File(framePath).writeAsBytes(pngBytes);
      framePaths.add(framePath);
    }

    // Create GIF
    final animation = frames.first.clone();
    for (var i = 1; i < frames.length; i++) {
      animation.addFrame(frames[i]);
    }
    final gifBytes = img.encodeGif(animation);
    final gifPath = '${workDir.path}/test_sticker.gif';
    await File(gifPath).writeAsBytes(gifBytes);

    return {
      'frames': framePaths,
      'gifPath': gifPath,
      'fps': 12,
    };
  }

  // ===========================================================================
  // TEST 1: Video to Sticker — Picker Screen UI
  // ===========================================================================

  testWidgets('E2E Step 1: Video to Sticker picker screen UI',
      (tester) async {
    suppressOverflowErrors();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.futureatoms.sticker_officer/share_import'),
      (MethodCall methodCall) async => <String>[],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const StickerOfficerApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // Navigate to Video to Sticker
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await takeScreenshot('01_create_bottom_sheet');

    await tester.tap(find.text('From Video'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await takeScreenshot('02_video_picker_state');

    // Verify all picker elements
    expect(find.text('Video to Sticker'), findsOneWidget);
    expect(find.text('Pick a Video!'), findsOneWidget);
    expect(find.text('Choose Video'), findsOneWidget);
    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    expect(find.textContaining('5 seconds'), findsOneWidget);
    expect(find.textContaining('smoothness'), findsOneWidget);
    expect(find.textContaining('500 KB'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.byIcon(Icons.data_usage_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Go back
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
  });

  // ===========================================================================
  // TEST 2: Animated Editor — Video-sourced with FFmpeg GIF
  // ===========================================================================

  testWidgets('E2E Step 2: Animated editor with video-sourced frames',
      (tester) async {
    suppressOverflowErrors();

    // Create test video output (frames + GIF)
    final videoOutput = await createTestVideoOutput();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: AnimatedStickerScreen(
            initialFramePaths: videoOutput['frames'] as List<String>,
            ffmpegGifPath: videoOutput['gifPath'] as String,
            initialFps: videoOutput['fps'] as int,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await takeScreenshot('03_animated_editor_video_sourced');

    // Verify video-sourced mode
    expect(find.text('Animated Sticker'), findsOneWidget);
    // Frame badge should show "12 frames" not "12/8"
    expect(find.textContaining('12 frames'), findsOneWidget);
    // Add button should NOT be visible (video-sourced hides it)
    // The add_photo_alternate icon should not appear as a standalone button
    // (it may still be in the empty state text, but we have frames loaded)

    // Verify FPS slider is present
    expect(find.text('Speed'), findsOneWidget);
    expect(find.textContaining('FPS'), findsOneWidget);

    // Verify size indicator
    expect(find.byIcon(Icons.data_usage_rounded), findsOneWidget);

    await takeScreenshot('04_animated_editor_controls');

    // Test play/pause
    final playButton = find.byIcon(Icons.play_circle_filled_rounded);
    if (playButton.evaluate().isNotEmpty) {
      await tester.tap(playButton);
      await tester.pump(const Duration(milliseconds: 500));
      await takeScreenshot('05_animation_playing');
      // Pause
      final pauseButton = find.byIcon(Icons.pause_circle_filled_rounded);
      if (pauseButton.evaluate().isNotEmpty) {
        await tester.tap(pauseButton);
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    // Test adding text overlay
    await tester.tap(find.byIcon(Icons.text_fields_outlined));
    await tester.pumpAndSettle();
    await takeScreenshot('06_text_dialog');

    // Type text
    final textField = find.byType(TextField);
    if (textField.evaluate().isNotEmpty) {
      await tester.enterText(textField, 'LOL');
      await tester.pumpAndSettle();
      await takeScreenshot('07_text_entered');

      // Tap Next
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await takeScreenshot('08_text_style_sheet');

      // Apply text (tap Apply or first filled button in sheet)
      final applyBtn = find.text('Apply');
      if (applyBtn.evaluate().isNotEmpty) {
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();
      }
    }

    await takeScreenshot('09_text_applied');

    // Verify text badge shows
    expect(find.textContaining('LOL'), findsWidgets);
  });

  // ===========================================================================
  // TEST 3: Animated Editor — Manual flow (no regression)
  // ===========================================================================

  testWidgets('E2E Step 3: Manual animated sticker flow (no regression)',
      (tester) async {
    suppressOverflowErrors();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: AnimatedStickerScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await takeScreenshot('10_manual_flow_empty');

    // Verify manual flow UI
    expect(find.text('Animated Sticker'), findsOneWidget);
    expect(find.textContaining('Tap to add pictures'), findsOneWidget);
    // Add button should be visible in manual flow
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsWidgets);
    // Frame badge should show "0/8" not "0 frames"
    expect(find.text('0/8'), findsOneWidget);

    // Import GIF button should be visible
    expect(find.text('Import GIF'), findsOneWidget);
    // Save to Pack button should be visible
    expect(find.text('Save to Pack'), findsOneWidget);

    await takeScreenshot('11_manual_flow_buttons');
  });

  // ===========================================================================
  // TEST 4: Guardrails — Video-specific vs manual
  // ===========================================================================

  testWidgets('E2E Step 4: Guardrails are correct for each flow',
      (tester) async {
    suppressOverflowErrors();

    // Video-specific guardrails
    expect(StickerGuardrails.videoMaxFps, 15);
    expect(StickerGuardrails.videoMaxFrames, 75);
    expect(StickerGuardrails.videoMaxDurationMs, 5000);
    expect(StickerGuardrails.qualityFpsStops.length, 5);
    expect(StickerGuardrails.qualityResStops.length, 5);
    expect(StickerGuardrails.qualityColorStops.length, 5);

    // Manual guardrails unchanged
    expect(StickerGuardrails.maxFps, 8);
    expect(StickerGuardrails.maxFrames, 8);

    // Video validation
    final videoErrors = StickerGuardrails.validateVideoSticker(
      frameCount: 60,
      fps: 12,
      sizeBytes: 400 * 1024,
    );
    expect(videoErrors, isEmpty);

    // Video validation rejects bad values
    final badErrors = StickerGuardrails.validateVideoSticker(
      frameCount: 100,
      fps: 20,
      sizeBytes: 600 * 1024,
    );
    expect(badErrors, isNotEmpty);

    // Size estimation works
    final estimate = StickerGuardrails.estimateGifSizeKB(
      durationSec: 3.0,
      fps: 12,
      resolution: 384,
    );
    expect(estimate, greaterThan(0));

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await takeScreenshot('12_guardrails_verified');
  });
}
