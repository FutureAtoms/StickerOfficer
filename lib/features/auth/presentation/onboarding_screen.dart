import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../data/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _pages = const [
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      title: 'Create Amazing Stickers',
      description:
          'Use AI to generate stickers from text, remove backgrounds with one tap, and add fun effects!',
      color: AppColors.coral,
    ),
    _OnboardingPage(
      icon: Icons.chat_rounded,
      title: 'Share on WhatsApp',
      description:
          'One-click export to WhatsApp. Your stickers, ready to send in seconds!',
      color: AppColors.whatsappGreen,
    ),
    _OnboardingPage(
      icon: Icons.people_rounded,
      title: 'Join the Community',
      description:
          'Discover trending stickers, join challenges, and share your creations with the world!',
      color: AppColors.purple,
    ),
  ];

  void _finishOnboarding() {
    ref.read(sharedPreferencesProvider).setBool('onboarding_complete', true);
    context.go('/home');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => _finishOnboarding(),
                child: const Text('Skip'),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) => _pages[index],
              ),
            ),
            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 28 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color:
                        _currentPage == i
                            ? AppColors.coral
                            : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Action button(s)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child:
                  _currentPage == _pages.length - 1
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BubblyButton(
                              label: 'Get Started',
                              gradient: AppColors.primaryGradient,
                              onPressed: () => _finishOnboarding(),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                _finishOnboarding();
                                context.push('/login');
                              },
                              child: const Text(
                                'or sign in with Google / Apple',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        )
                      : BubblyButton(
                        label: 'Next',
                        color: AppColors.coral,
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon container
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 64, color: color),
          )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.08, duration: 2000.ms, curve: Curves.easeInOut),
          const SizedBox(height: 40),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(color: color),
            textAlign: TextAlign.center,
          )
          .animate()
          .fadeIn(duration: 600.ms, delay: 200.ms)
          .slideY(begin: 0.3, end: 0, duration: 600.ms, delay: 200.ms),
          const SizedBox(height: 16),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          )
          .animate()
          .fadeIn(duration: 600.ms, delay: 400.ms)
          .slideY(begin: 0.3, end: 0, duration: 600.ms, delay: 400.ms),
        ],
      ),
    );
  }
}
