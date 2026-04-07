import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/providers.dart';

/// A modern loading screen shown on first launch while seed data loads
/// and auth initializes. Replaces the static native splash with an
/// animated experience.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  String _status = 'Starting up...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Step 1: Auth
      setState(() {
        _status = 'Connecting...';
        _progress = 0.2;
      });
      await ref.read(authStateProvider.future);

      if (!mounted) return;
      setState(() {
        _status = 'Loading stickers...';
        _progress = 0.5;
      });

      // Step 2: Packs (this triggers the seed on first launch)
      await ref.read(packsProvider.future);

      if (!mounted) return;
      setState(() {
        _status = 'Almost ready...';
        _progress = 0.9;
      });

      // Small delay for visual polish
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      setState(() => _progress = 1.0);
      await Future.delayed(const Duration(milliseconds: 200));

      // Navigate to the appropriate screen
      if (!mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final hasSeenOnboarding = prefs.getBool('onboarding_complete') ?? false;
      if (hasSeenOnboarding) {
        context.go('/home');
      } else {
        context.go('/onboarding');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Ready!');
      // Even if loading fails, navigate forward
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated app icon
            Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: const DecorationImage(
                      image: AssetImage('assets/images/app_icon.png'),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.coral.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                  begin: 1.0,
                  end: 1.06,
                  duration: 1500.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 40),
            // App name
            Text(
              'StickerOfficer',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                foreground:
                    Paint()
                      ..shader = const LinearGradient(
                        colors: [AppColors.coral, AppColors.purple],
                      ).createShader(const Rect.fromLTWH(0, 0, 250, 40)),
              ),
            ).animate().fadeIn(duration: 600.ms, delay: 200.ms),
            const SizedBox(height: 32),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      height: 6,
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: AppColors.coral.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.coral,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _status,
                      key: ValueKey(_status),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
          ],
        ),
      ),
    );
  }
}
