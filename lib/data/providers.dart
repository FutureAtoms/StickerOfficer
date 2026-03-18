import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
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
  FutureOr<List<StickerPack>> build() async {
    await _seedDemoDataIfEmpty();
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

  // ===========================================================================
  // Seed / demo data
  // ===========================================================================

  /// Populates the repository with demo packs when the store is empty.
  /// Called once during [build]; no-ops if packs already exist.
  Future<void> _seedDemoDataIfEmpty() async {
    final existing = _repo.getPacks();
    if (existing.isNotEmpty) return;

    final uuid = ref.read(uuidProvider);
    final appDir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();

    // Each entry: name, stickerCount, tags, bgColor (ARGB int), accentColor
    final demoPacks = <_DemoPackSpec>[
      _DemoPackSpec(
        name: 'Cute Animals',
        stickerCount: 3,
        tags: ['cute', 'animals'],
        bgColor: img.ColorRgba8(255, 224, 224, 255), // pink
        accentColor: img.ColorRgba8(255, 107, 107, 255), // coral
        shape: _StickerShape.circle,
        authorName: 'StickerOfficer',
        likeCount: 87,
        downloadCount: 214,
      ),
      _DemoPackSpec(
        name: 'Funny Reactions',
        stickerCount: 5,
        tags: ['funny', 'reaction', 'meme'],
        bgColor: img.ColorRgba8(224, 240, 255, 255), // blue
        accentColor: img.ColorRgba8(59, 130, 246, 255), // bright blue
        shape: _StickerShape.star,
        authorName: 'MemeKing',
        likeCount: 312,
        downloadCount: 578,
      ),
      _DemoPackSpec(
        name: 'Food & Drinks',
        stickerCount: 4,
        tags: ['food', 'drinks'],
        bgColor: img.ColorRgba8(255, 240, 224, 255), // orange
        accentColor: img.ColorRgba8(251, 146, 60, 255), // orange
        shape: _StickerShape.diamond,
        authorName: 'FoodieArt',
        likeCount: 156,
        downloadCount: 340,
      ),
      _DemoPackSpec(
        name: 'Emoji Remix',
        stickerCount: 3,
        tags: ['emoji', 'remix'],
        bgColor: img.ColorRgba8(232, 224, 255, 255), // lavender
        accentColor: img.ColorRgba8(168, 85, 247, 255), // purple
        shape: _StickerShape.heart,
        authorName: 'EmojiLab',
        likeCount: 243,
        downloadCount: 491,
      ),
      _DemoPackSpec(
        name: 'Motivational',
        stickerCount: 3,
        tags: ['motivation', 'quotes'],
        bgColor: img.ColorRgba8(224, 255, 224, 255), // green
        accentColor: img.ColorRgba8(6, 214, 160, 255), // teal
        shape: _StickerShape.star,
        authorName: 'InspireDaily',
        likeCount: 198,
        downloadCount: 425,
      ),
    ];

    for (var i = 0; i < demoPacks.length; i++) {
      final spec = demoPacks[i];
      final packId = uuid.v4();
      final packDir = '${appDir.path}/stickers/$packId';
      await Directory(packDir).create(recursive: true);

      final stickerPaths = <String>[];
      String? trayPath;

      for (var s = 0; s < spec.stickerCount; s++) {
        final filePath = '$packDir/sticker_$s.png';
        final image = _generateStickerImage(spec: spec, index: s);
        final pngBytes = img.encodePng(image);
        await File(filePath).writeAsBytes(pngBytes);
        stickerPaths.add(filePath);

        // Use the first sticker as the tray icon.
        trayPath ??= filePath;
      }

      final pack = StickerPack(
        id: packId,
        name: spec.name,
        authorName: spec.authorName,
        stickerPaths: stickerPaths,
        trayIconPath: trayPath,
        likeCount: spec.likeCount,
        downloadCount: spec.downloadCount,
        createdAt: now.subtract(Duration(days: (demoPacks.length - i) * 2)),
        isPublic: true,
        tags: spec.tags,
      );

      await _repo.savePack(pack);
    }
  }

  /// Generates a 512x512 placeholder sticker image.
  img.Image _generateStickerImage({
    required _DemoPackSpec spec,
    required int index,
  }) {
    const size = 512;
    final image = img.Image(width: size, height: size);

    // Fill with background colour.
    img.fill(image, color: spec.bgColor);

    // Vary the accent slightly per sticker in the pack so they're distinct.
    final accent = _shiftHue(spec.accentColor, index * 25);

    // Draw the main shape centred in the image.
    switch (spec.shape) {
      case _StickerShape.circle:
        _drawFilledCircle(
          image,
          size ~/ 2,
          size ~/ 2,
          160 - index * 15,
          accent,
        );
        // Inner highlight circle
        _drawFilledCircle(
          image,
          size ~/ 2 - 30,
          size ~/ 2 - 30,
          40,
          img.ColorRgba8(255, 255, 255, 140),
        );
        break;
      case _StickerShape.star:
        _drawStar(image, size ~/ 2, size ~/ 2, 180 - index * 10, 5, accent);
        break;
      case _StickerShape.diamond:
        _drawDiamond(image, size ~/ 2, size ~/ 2, 170 - index * 12, accent);
        break;
      case _StickerShape.heart:
        _drawHeart(image, size ~/ 2, size ~/ 2, 140 - index * 10, accent);
        break;
    }

    // Draw a small decorative circle in the corner for visual interest.
    _drawFilledCircle(image, 80, 80, 30 + index * 5, accent);

    return image;
  }

  // -------------------------------------------------------------------------
  // Drawing primitives
  // -------------------------------------------------------------------------

  void _drawFilledCircle(
    img.Image image,
    int cx,
    int cy,
    int radius,
    img.Color color,
  ) {
    img.fillCircle(image, x: cx, y: cy, radius: radius, color: color);
  }

  void _drawStar(
    img.Image image,
    int cx,
    int cy,
    int outerRadius,
    int points,
    img.Color color,
  ) {
    final innerRadius = outerRadius ~/ 2;
    final vertices = <Point<int>>[];
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi / points) - (pi / 2);
      final r = i.isEven ? outerRadius : innerRadius;
      vertices.add(
        Point<int>(
          cx + (r * cos(angle)).round(),
          cy + (r * sin(angle)).round(),
        ),
      );
    }
    _fillPolygon(image, vertices, color);
  }

  void _drawDiamond(
    img.Image image,
    int cx,
    int cy,
    int halfSize,
    img.Color color,
  ) {
    final vertices = <Point<int>>[
      Point<int>(cx, cy - halfSize), // top
      Point<int>(cx + halfSize, cy), // right
      Point<int>(cx, cy + halfSize), // bottom
      Point<int>(cx - halfSize, cy), // left
    ];
    _fillPolygon(image, vertices, color);
  }

  void _drawHeart(img.Image image, int cx, int cy, int size, img.Color color) {
    // Approximate heart with two circles and a triangle.
    final r = size ~/ 2;
    _drawFilledCircle(image, cx - r ~/ 2, cy - r ~/ 3, r, color);
    _drawFilledCircle(image, cx + r ~/ 2, cy - r ~/ 3, r, color);
    final vertices = <Point<int>>[
      Point<int>(cx - size, cy),
      Point<int>(cx + size, cy),
      Point<int>(cx, cy + size),
    ];
    _fillPolygon(image, vertices, color);
  }

  /// Simple scan-line polygon fill.
  void _fillPolygon(
    img.Image image,
    List<Point<int>> vertices,
    img.Color color,
  ) {
    if (vertices.isEmpty) return;
    var minY = vertices.first.y;
    var maxY = vertices.first.y;
    for (final v in vertices) {
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }
    minY = minY.clamp(0, image.height - 1);
    maxY = maxY.clamp(0, image.height - 1);

    for (var y = minY; y <= maxY; y++) {
      final intersections = <int>[];
      for (var i = 0; i < vertices.length; i++) {
        final j = (i + 1) % vertices.length;
        final yi = vertices[i].y;
        final yj = vertices[j].y;
        if ((yi <= y && yj > y) || (yj <= y && yi > y)) {
          final xi = vertices[i].x;
          final xj = vertices[j].x;
          final x = xi + ((y - yi) * (xj - xi)) ~/ (yj - yi);
          intersections.add(x);
        }
      }
      intersections.sort();
      for (var k = 0; k + 1 < intersections.length; k += 2) {
        final startX = intersections[k].clamp(0, image.width - 1);
        final endX = intersections[k + 1].clamp(0, image.width - 1);
        for (var x = startX; x <= endX; x++) {
          image.setPixel(x, y, color);
        }
      }
    }
  }

  /// Shifts the hue of [color] by [degrees].
  img.ColorRgba8 _shiftHue(img.Color color, int degrees) {
    final r = color.r.toInt();
    final g = color.g.toInt();
    final b = color.b.toInt();
    final a = color.a.toInt();

    // Convert RGB -> HSL, shift hue, convert back.
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;

    final maxC = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
    final minC = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
    final delta = maxC - minC;

    double hue = 0;
    if (delta > 0) {
      if (maxC == rf) {
        hue = 60 * (((gf - bf) / delta) % 6);
      } else if (maxC == gf) {
        hue = 60 * (((bf - rf) / delta) + 2);
      } else {
        hue = 60 * (((rf - gf) / delta) + 4);
      }
    }
    final lightness = (maxC + minC) / 2;
    final saturation =
        delta == 0 ? 0.0 : delta / (1 - (2 * lightness - 1).abs());

    hue = (hue + degrees) % 360;
    if (hue < 0) hue += 360;

    // HSL -> RGB
    final c = (1 - (2 * lightness - 1).abs()) * saturation;
    final x = c * (1 - ((hue / 60) % 2 - 1).abs());
    final m = lightness - c / 2;
    double r1, g1, b1;
    if (hue < 60) {
      r1 = c;
      g1 = x;
      b1 = 0;
    } else if (hue < 120) {
      r1 = x;
      g1 = c;
      b1 = 0;
    } else if (hue < 180) {
      r1 = 0;
      g1 = c;
      b1 = x;
    } else if (hue < 240) {
      r1 = 0;
      g1 = x;
      b1 = c;
    } else if (hue < 300) {
      r1 = x;
      g1 = 0;
      b1 = c;
    } else {
      r1 = c;
      g1 = 0;
      b1 = x;
    }

    return img.ColorRgba8(
      ((r1 + m) * 255).round().clamp(0, 255),
      ((g1 + m) * 255).round().clamp(0, 255),
      ((b1 + m) * 255).round().clamp(0, 255),
      a,
    );
  }
}

// =============================================================================
// Seed data helpers (private to this file)
// =============================================================================

enum _StickerShape { circle, star, diamond, heart }

class _DemoPackSpec {
  final String name;
  final int stickerCount;
  final List<String> tags;
  final img.Color bgColor;
  final img.Color accentColor;
  final _StickerShape shape;
  final String authorName;
  final int likeCount;
  final int downloadCount;

  const _DemoPackSpec({
    required this.name,
    required this.stickerCount,
    required this.tags,
    required this.bgColor,
    required this.accentColor,
    required this.shape,
    required this.authorName,
    this.likeCount = 0,
    this.downloadCount = 0,
  });
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
