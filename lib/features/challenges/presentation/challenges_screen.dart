import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/providers.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(challengesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sticker Challenges')),
      body: challengesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _empty(context),
        data: (challenges) {
          if (challenges.isEmpty) return _empty(context);

          final activeChallenges =
              challenges.where((c) => c.isActive || c.isVoting).toList();
          final pastChallenges =
              challenges.where((c) => c.isCompleted).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (activeChallenges.isNotEmpty) ...[
                ...activeChallenges.asMap().entries.map((entry) {
                  final challenge = entry.value;
                  final i = entry.key;
                  final daysLeft = challenge.endDate
                      .difference(DateTime.now())
                      .inDays
                      .clamp(0, 999);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      label:
                          '${challenge.title}, ${challenge.isActive ? "$daysLeft days left" : "Voting"}, ${challenge.submissionCount} submissions',
                      child: _ChallengeDetailCard(
                        title: challenge.title,
                        description: challenge.description,
                        daysLeft: daysLeft,
                        submissions: challenge.submissionCount,
                        isActive: challenge.isActive,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: (i * 120).ms)
                      .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 500.ms,
                          delay: (i * 120).ms,
                          curve: Curves.easeOutCubic);
                }),
              ],
              if (pastChallenges.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Past Challenges',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ...pastChallenges.asMap().entries.map(
                  (entry) => _PastChallengeItem(
                    title: entry.value.title,
                    winner: entry.value.winnerName ?? 'TBD',
                    submissions: entry.value.submissionCount,
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: (entry.key * 80).ms)
                      .slideX(
                          begin: -0.1,
                          end: 0,
                          duration: 400.ms,
                          delay: (entry.key * 80).ms),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_rounded,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No challenges available right now',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ChallengeDetailCard extends StatelessWidget {
  final String title;
  final String description;
  final int daysLeft;
  final int submissions;
  final bool isActive;

  const _ChallengeDetailCard({
    required this.title,
    required this.description,
    required this.daysLeft,
    required this.submissions,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.coral, AppColors.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha:0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  isActive ? '$daysLeft days left' : 'Voting',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.9),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '$submissions submissions',
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.8),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  isActive ? 'Submit Pack' : 'Vote',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PastChallengeItem extends StatelessWidget {
  final String title;
  final String winner;
  final int submissions;

  const _PastChallengeItem({
    required this.title,
    required this.winner,
    required this.submissions,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title challenge. Winner: $winner, $submissions entries',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowLight,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.amber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Winner: $winner  \u2022  $submissions entries',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
