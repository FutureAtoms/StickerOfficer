import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/editor/presentation/bulk_edit_screen.dart';
import '../../features/editor/presentation/bulk_video_import_screen.dart';
import '../../features/editor/presentation/animated_sticker_screen.dart';
import '../../features/editor/presentation/video_to_sticker_screen.dart';
import '../../features/packs/presentation/my_packs_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/packs/presentation/pack_detail_screen.dart';
import '../../features/ai_generate/presentation/ai_prompt_screen.dart';
import '../../features/challenges/presentation/challenges_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../widgets/main_shell.dart';
import '../../data/providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final prefs = ref.read(sharedPreferencesProvider);
      final hasSeenOnboarding = prefs.getBool('onboarding_complete') ?? false;
      final location = state.matchedLocation;

      // Don't redirect if already on onboarding or login
      if (location == '/onboarding' || location == '/login') return null;

      // Don't redirect if navigating to a pack (import deep link)
      if (location.startsWith('/pack/')) return null;

      if (!hasSeenOnboarding) return '/onboarding';
      return null;
    },
    errorBuilder:
        (context, state) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_emotions_rounded,
                    size: 80,
                    color: AppColors.coral.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Oops! Page not found',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The sticker you\'re looking for ran away!',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Go Home'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.coral,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    routes: [
      // Auth
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
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
          // extra can be:
          //   null        → blank editor
          //   String      → imagePath
          //   Map<String, dynamic> → imagePath, packId, bulkMode
          final extra = state.extra;
          String? imagePath;
          String? packId;
          bool bulkMode = false;
          if (extra is String) {
            imagePath = extra;
          } else if (extra is Map<String, dynamic>) {
            imagePath = extra['imagePath'] as String?;
            packId = extra['packId'] as String?;
            bulkMode = extra['bulkMode'] as bool? ?? false;
          }
          return EditorScreen(
            imagePath: imagePath,
            targetPackId: packId,
            bulkMode: bulkMode,
          );
        },
      ),
      GoRoute(
        path: '/bulk-editor/:packId',
        builder: (context, state) {
          final packId = state.pathParameters['packId']!;
          return BulkEditScreen(packId: packId);
        },
      ),
      GoRoute(
        path: '/bulk-video-editor/:packId',
        builder: (context, state) {
          final packId = state.pathParameters['packId']!;
          return BulkVideoImportScreen(packId: packId);
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
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return AnimatedStickerScreen(
              initialFramePaths: extra['frames'] as List<String>?,
              ffmpegGifPath: extra['gifPath'] as String?,
              initialFps: extra['fps'] as int?,
              bulkMode: extra['bulkMode'] as bool? ?? false,
            );
          }
          return AnimatedStickerScreen(
            initialFramePaths: extra as List<String>?,
          );
        },
      ),
      GoRoute(
        path: '/video-to-sticker',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return VideoToStickerScreen(
              initialVideoPath: extra['initialVideoPath'] as String?,
              bulkMode: extra['bulkMode'] as bool? ?? false,
            );
          }
          return const VideoToStickerScreen();
        },
      ),
      GoRoute(
        path: '/challenges',
        builder: (context, state) => const ChallengesScreen(),
      ),
    ],
  );
});
