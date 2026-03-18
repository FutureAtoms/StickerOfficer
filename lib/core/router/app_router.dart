import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/editor/presentation/animated_sticker_screen.dart';
import '../../features/packs/presentation/my_packs_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/packs/presentation/pack_detail_screen.dart';
import '../../features/ai_generate/presentation/ai_prompt_screen.dart';
import '../../features/challenges/presentation/challenges_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../widgets/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      // Onboarding
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Main shell with bottom nav
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder:
                (context, state) => const NoTransitionPage(child: FeedScreen()),
          ),
          GoRoute(
            path: '/explore',
            pageBuilder:
                (context, state) =>
                    const NoTransitionPage(child: SearchScreen()),
          ),
          GoRoute(
            path: '/my-packs',
            pageBuilder:
                (context, state) =>
                    const NoTransitionPage(child: MyPacksScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder:
                (context, state) =>
                    const NoTransitionPage(child: ProfileScreen()),
          ),
        ],
      ),
      // Full-screen routes
      GoRoute(
        path: '/editor',
        builder: (context, state) {
          final imagePath = state.extra as String?;
          return EditorScreen(imagePath: imagePath);
        },
      ),
      GoRoute(
        path: '/ai-generate',
        builder: (context, state) => const AiPromptScreen(),
      ),
      GoRoute(
        path: '/pack/:id',
        builder: (context, state) {
          final packId = state.pathParameters['id']!;
          return PackDetailScreen(packId: packId);
        },
      ),
      GoRoute(
        path: '/animated-editor',
        builder: (context, state) => const AnimatedStickerScreen(),
      ),
      GoRoute(
        path: '/challenges',
        builder: (context, state) => const ChallengesScreen(),
      ),
    ],
  );
});
