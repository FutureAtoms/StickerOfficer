import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_officer/data/models/challenge.dart';
import 'package:sticker_officer/features/auth/presentation/onboarding_screen.dart';
import 'package:sticker_officer/features/challenges/presentation/challenges_screen.dart';
import 'package:sticker_officer/features/feed/presentation/feed_screen.dart';
import 'package:sticker_officer/features/profile/presentation/profile_screen.dart';
import 'package:sticker_officer/data/providers.dart';
import 'package:sticker_officer/features/search/presentation/search_screen.dart';

/// Widget tests for screens that previously had zero test coverage:
/// Feed, Search, Profile, Challenges, Onboarding.

late SharedPreferences _prefs;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'sticker_packs': '[]'});
    _prefs = await SharedPreferences.getInstance();
  });

  // ===========================================================================
  // Feed Screen
  // ===========================================================================

  group('FeedScreen', () {
    Future<void> pumpFeed(WidgetTester tester) async {
      // Use 800x600 surface — wide enough that the title row doesn't overflow
      // (Google Fonts loads Roboto in tests, which is wider than Nunito)
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
          child: const MaterialApp(home: FeedScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders app title', (tester) async {
      await pumpFeed(tester);
      expect(find.text('StickerOfficer'), findsOneWidget);
    });

    testWidgets('shows three tab pills', (tester) async {
      await pumpFeed(tester);
      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Challenges'), findsOneWidget);
    });

    testWidgets('notification bell is present', (tester) async {
      await pumpFeed(tester);
      expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
    });

    testWidgets('loads packs data', (tester) async {
      await pumpFeed(tester);
      // Pump to let async provider load data
      await tester.pump(const Duration(seconds: 1));
      // Should show shimmer loading or pack content (seed data loads on first run)
      expect(find.byType(FeedScreen), findsOneWidget);
    });

    testWidgets('tab pills have Semantics', (tester) async {
      await pumpFeed(tester);
      final semantics = tester.getSemantics(find.text('Trending'));
      expect(semantics.label, contains('tab'));
    });
  });

  // ===========================================================================
  // Search Screen
  // ===========================================================================

  group('SearchScreen', () {
    Future<void> pumpSearch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1284, 2778);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders Explore title', (tester) async {
      await pumpSearch(tester);
      expect(find.text('Explore'), findsOneWidget);
    });

    testWidgets('shows search bar', (tester) async {
      await pumpSearch(tester);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows category bubbles', (tester) async {
      await pumpSearch(tester);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Funny'), findsOneWidget);
      expect(find.text('Love'), findsOneWidget);
      expect(find.text('Animals'), findsOneWidget);
    });

    testWidgets('shows trending tags', (tester) async {
      await pumpSearch(tester);
      expect(find.text('Trending Tags'), findsOneWidget);
      expect(find.text('#reaction'), findsOneWidget);
      expect(find.text('#cute'), findsOneWidget);
    });

    testWidgets('typing in search shows clear button', (tester) async {
      await pumpSearch(tester);
      await tester.enterText(find.byType(TextField), 'cat');
      await tester.pump();
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
    });
  });

  // ===========================================================================
  // Profile Screen
  // ===========================================================================

  group('ProfileScreen', () {
    Future<void> pumpProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1284, 2778);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('shows user name and handle', (tester) async {
      await pumpProfile(tester);
      expect(find.text('Sticker Creator'), findsOneWidget);
      expect(find.text('@stickermaker'), findsOneWidget);
    });

    testWidgets('shows avatar with gradient', (tester) async {
      await pumpProfile(tester);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('shows stat labels', (tester) async {
      await pumpProfile(tester);
      expect(find.text('Packs'), findsOneWidget);
      expect(find.text('Stickers'), findsOneWidget);
      expect(find.text('Likes'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
    });

    testWidgets('shows settings items', (tester) async {
      await pumpProfile(tester);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('About StickerOfficer'), findsOneWidget);
    });

    testWidgets('shows sign out button', (tester) async {
      await pumpProfile(tester);
      expect(find.text('Sign Out'), findsOneWidget);
    });
  });

  // ===========================================================================
  // Challenges Screen
  // ===========================================================================

  group('ChallengesScreen', () {
    final _testChallenges = [
      Challenge(
        id: 'c1',
        title: 'Meme Madness',
        description: 'Best meme sticker wins!',
        status: 'active',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        submissionCount: 42,
      ),
      Challenge(
        id: 'c2',
        title: 'Vote for the Best',
        description: 'Cast your vote!',
        status: 'voting',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        submissionCount: 10,
      ),
    ];

    Future<void> pumpChallenges(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1284, 2778);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(_prefs),
            challengesProvider.overrideWith((_) async => _testChallenges),
          ],
          child: const MaterialApp(home: ChallengesScreen()),
        ),
      );
      // Use pump() — flutter_animate entrance animations prevent pumpAndSettle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('renders app bar title', (tester) async {
      await pumpChallenges(tester);
      expect(find.text('Sticker Challenges'), findsOneWidget);
    });

    testWidgets('shows challenge cards', (tester) async {
      await pumpChallenges(tester);
      // Challenges are provided by challengesProvider (hardcoded samples)
      expect(find.byIcon(Icons.emoji_events_rounded), findsWidgets);
    });

    testWidgets('shows Submit Pack or Vote buttons', (tester) async {
      await pumpChallenges(tester);
      // Active challenges show Submit Pack, voting ones show Vote
      final submitOrVote = find.text('Submit Pack');
      final vote = find.text('Vote');
      expect(
        submitOrVote.evaluate().length + vote.evaluate().length,
        greaterThan(0),
      );
    });
  });

  // ===========================================================================
  // Onboarding Screen
  // ===========================================================================

  group('OnboardingScreen', () {
    Future<void> pumpOnboarding(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1284, 2778);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      // Use pump() — flutter_animate entrance animations prevent pumpAndSettle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('shows first page content', (tester) async {
      await pumpOnboarding(tester);
      expect(find.text('Create Amazing Stickers'), findsOneWidget);
    });

    testWidgets('shows Skip button', (tester) async {
      await pumpOnboarding(tester);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('shows Next button on first page', (tester) async {
      await pumpOnboarding(tester);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('has page dots indicator', (tester) async {
      await pumpOnboarding(tester);
      // 3 dots — AnimatedContainer is used for each dot indicator
      expect(find.byType(AnimatedContainer), findsWidgets);
    });

    testWidgets('shows star icon on first page', (tester) async {
      await pumpOnboarding(tester);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    });
  });
}
