import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/challenge.dart';
import 'models/sticker_pack.dart';
import 'repositories/pack_repository.dart';

// =============================================================================
// SharedPreferences singleton
// =============================================================================

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  // Must be overridden in ProviderScope at app startup.
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a concrete instance. '
    'Call SharedPreferences.getInstance() before runApp and pass the result '
    'via ProviderScope overrides.',
  );
});

// =============================================================================
// Repository
// =============================================================================

final packRepositoryProvider = Provider<PackRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PackRepository(prefs);
});

// =============================================================================
// UUID helper
// =============================================================================

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

// =============================================================================
// Packs – AsyncNotifier
// =============================================================================

final packsProvider = AsyncNotifierProvider<PacksNotifier, List<StickerPack>>(
  PacksNotifier.new,
);

class PacksNotifier extends AsyncNotifier<List<StickerPack>> {
  PackRepository get _repo => ref.read(packRepositoryProvider);

  @override
  FutureOr<List<StickerPack>> build() {
    return _repo.getPacks();
  }

  /// Adds a brand-new pack and refreshes state.
  Future<void> addPack(StickerPack pack) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.savePack(pack);
      return _repo.getPacks();
    });
  }

  /// Updates an existing pack's metadata.
  Future<void> updatePack(StickerPack pack) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.updatePack(pack);
      return _repo.getPacks();
    });
  }

  /// Deletes a pack by its [id].
  Future<void> deletePack(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.deletePack(id);
      return _repo.getPacks();
    });
  }

  /// Forces a reload from SharedPreferences.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => _repo.getPacks());
  }
}

// =============================================================================
// Selected pack
// =============================================================================

final selectedPackProvider = StateProvider<StickerPack?>((ref) => null);

// =============================================================================
// Search
// =============================================================================

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = Provider<AsyncValue<List<StickerPack>>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final packsAsync = ref.watch(packsProvider);

  return packsAsync.whenData((packs) {
    if (query.trim().isEmpty) return packs;

    final lowerQuery = query.toLowerCase();
    return packs.where((pack) {
      final nameMatch = pack.name.toLowerCase().contains(lowerQuery);
      final tagMatch = pack.tags.any(
        (tag) => tag.toLowerCase().contains(lowerQuery),
      );
      final authorMatch = pack.authorName.toLowerCase().contains(lowerQuery);
      return nameMatch || tagMatch || authorMatch;
    }).toList();
  });
});

// =============================================================================
// Challenges – hardcoded sample data for now
// =============================================================================

final challengesProvider = Provider<List<Challenge>>((ref) {
  final now = DateTime.now();
  return [
    Challenge(
      id: 'challenge-1',
      title: 'Funny Animals',
      description: 'Create the funniest animal stickers!',
      status: 'active',
      startDate: now.subtract(const Duration(days: 4)),
      endDate: now.add(const Duration(days: 3)),
      submissionCount: 142,
    ),
    Challenge(
      id: 'challenge-2',
      title: 'Reaction Stickers',
      description: 'Express every emotion with creative reaction stickers.',
      status: 'voting',
      startDate: now.subtract(const Duration(days: 10)),
      endDate: now.subtract(const Duration(days: 1)),
      submissionCount: 89,
    ),
    Challenge(
      id: 'challenge-3',
      title: 'Meme Legends',
      description: 'Turn classic memes into sticker packs.',
      status: 'completed',
      startDate: now.subtract(const Duration(days: 30)),
      endDate: now.subtract(const Duration(days: 14)),
      submissionCount: 217,
      winnerName: 'StickerMaster42',
    ),
    Challenge(
      id: 'challenge-4',
      title: 'Holiday Vibes',
      description: 'Design festive stickers for any holiday!',
      status: 'active',
      startDate: now.subtract(const Duration(days: 2)),
      endDate: now.add(const Duration(days: 5)),
      submissionCount: 38,
    ),
  ];
});

// =============================================================================
// User stats – derived from packs
// =============================================================================

final userStatsProvider = Provider<AsyncValue<UserStats>>((ref) {
  final packsAsync = ref.watch(packsProvider);

  return packsAsync.whenData((packs) {
    final totalStickers = packs.fold<int>(
      0,
      (sum, p) => sum + p.stickerPaths.length,
    );
    final totalLikes = packs.fold<int>(0, (sum, p) => sum + p.likeCount);
    final totalDownloads = packs.fold<int>(
      0,
      (sum, p) => sum + p.downloadCount,
    );

    return UserStats(
      packCount: packs.length,
      totalStickers: totalStickers,
      totalLikes: totalLikes,
      totalDownloads: totalDownloads,
    );
  });
});

class UserStats {
  final int packCount;
  final int totalStickers;
  final int totalLikes;
  final int totalDownloads;

  const UserStats({
    required this.packCount,
    required this.totalStickers,
    required this.totalLikes,
    required this.totalDownloads,
  });

  @override
  String toString() =>
      'UserStats(packs: $packCount, stickers: $totalStickers, '
      'likes: $totalLikes, downloads: $totalDownloads)';
}
