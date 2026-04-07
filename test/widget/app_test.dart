import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/app.dart';
import 'package:sticker_officer/data/providers.dart';

void main() {
  group('StickerOfficer App', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('app renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const StickerOfficerApp(),
        ),
      );
      // Pump a few frames (don't settle — loading screen has looping animations)
      await tester.pump(const Duration(seconds: 1));

      // The app should render a MaterialApp via MaterialApp.router
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('shows loading screen on startup', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const StickerOfficerApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Loading screen shows app name and progress
      expect(find.text('StickerOfficer'), findsOneWidget);
    });

    testWidgets('theme uses Material 3', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const StickerOfficerApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Find the MaterialApp and verify its theme has useMaterial3 enabled
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme?.useMaterial3, isTrue);
      expect(materialApp.darkTheme?.useMaterial3, isTrue);
    });
  });
}
