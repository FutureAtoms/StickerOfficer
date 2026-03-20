import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/app.dart';
import 'package:sticker_officer/data/providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> pumpApp(WidgetTester tester) async {
    suppressOverflowErrors();

    // Mock platform channels not available on simulator
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.futureatoms.sticker_officer/share_import'),
      (MethodCall methodCall) async => <String>[],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.futureatoms.sticker_officer/whatsapp'),
      (MethodCall methodCall) async => false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const StickerOfficerApp(),
      ),
    );
    // Use pump with explicit duration — shimmer animations never settle
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('Video to Sticker screen — navigation and UI validation',
      (tester) async {
    await pumpApp(tester);

    // Step 1: Tap create button in bottom nav (add_circle icon)
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Step 2: Verify bottom sheet shows "From Video" option
    expect(find.text('From Video'), findsOneWidget);

    // Step 3: Tap "From Video"
    await tester.tap(find.text('From Video'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Step 4: Verify Video to Sticker screen loaded with all elements
    expect(find.text('Video to Sticker'), findsOneWidget);
    expect(find.text('Pick a Video!'), findsOneWidget);
    expect(find.text('Choose Video'), findsOneWidget);
    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.video_call_rounded), findsOneWidget);
    expect(find.textContaining('5 seconds'), findsOneWidget);
    expect(find.textContaining('smoothness'), findsOneWidget);
    expect(find.textContaining('500 KB'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Step 5: Close navigates back
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Step 6: Navigate to Animated Sticker (manual flow) — no regression
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animated Sticker'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Animated Sticker'), findsOneWidget);
    // Add-frame button visible in manual flow
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsWidgets);
  });
}
