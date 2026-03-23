import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sticker_officer/app.dart';

void main() {
  group('StickerOfficer App', () {
    testWidgets('app renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: StickerOfficerApp()),
      );
      await tester.pumpAndSettle();

      // The app should render a MaterialApp via MaterialApp.router
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('shows bottom navigation bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: StickerOfficerApp()),
      );
      await tester.pumpAndSettle();

      // Verify all navigation items are present
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('My Packs'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Center create button with gradient
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('displays StickerOfficer title in feed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: StickerOfficerApp()),
      );
      await tester.pumpAndSettle();

      // The FeedScreen header shows 'StickerOfficer' text
      expect(find.text('StickerOfficer'), findsOneWidget);
    });

    testWidgets('theme uses Material 3', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: StickerOfficerApp()),
      );
      await tester.pumpAndSettle();

      // Find the MaterialApp and verify its theme has useMaterial3 enabled
      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(materialApp.theme?.useMaterial3, isTrue);
      expect(materialApp.darkTheme?.useMaterial3, isTrue);
    });
  });
}
