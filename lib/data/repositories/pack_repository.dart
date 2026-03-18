import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sticker_pack.dart';

/// Local repository for sticker pack storage.
///
/// Pack metadata (JSON) is persisted in SharedPreferences.
/// Sticker image files live on the filesystem under the app's documents
/// directory; only their paths are stored in the pack metadata.
class PackRepository {
  static const _packsKey = 'sticker_packs';

  final SharedPreferences _prefs;

  PackRepository(this._prefs);

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns all saved packs, sorted by creation date (newest first).
  List<StickerPack> getPacks() {
    final raw = _prefs.getStringList(_packsKey) ?? [];
    final packs = raw.map((json) => StickerPack.fromJsonString(json)).toList();
    packs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return packs;
  }

  /// Returns a single pack by [id], or `null` if not found.
  StickerPack? getPack(String id) {
    final packs = getPacks();
    try {
      return packs.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Simple substring search across pack name and tags.
  List<StickerPack> searchPacks(String query) {
    if (query.trim().isEmpty) return getPacks();

    final lowerQuery = query.toLowerCase();
    return getPacks().where((pack) {
      final nameMatch = pack.name.toLowerCase().contains(lowerQuery);
      final tagMatch = pack.tags.any(
        (tag) => tag.toLowerCase().contains(lowerQuery),
      );
      final authorMatch = pack.authorName.toLowerCase().contains(lowerQuery);
      return nameMatch || tagMatch || authorMatch;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Saves a new pack. If a pack with the same [id] already exists it will be
  /// replaced (upsert behaviour).
  Future<void> savePack(StickerPack pack) async {
    final packs = getPacks();
    final index = packs.indexWhere((p) => p.id == pack.id);
    if (index >= 0) {
      packs[index] = pack;
    } else {
      packs.add(pack);
    }
    await _persist(packs);
  }

  /// Updates an existing pack. Throws [StateError] if the pack is not found.
  Future<void> updatePack(StickerPack pack) async {
    final packs = getPacks();
    final index = packs.indexWhere((p) => p.id == pack.id);
    if (index < 0) {
      throw StateError('Pack with id ${pack.id} not found');
    }
    packs[index] = pack;
    await _persist(packs);
  }

  /// Deletes the pack with the given [id]. No-op if not found.
  Future<void> deletePack(String id) async {
    final packs = getPacks();
    packs.removeWhere((p) => p.id == id);
    await _persist(packs);
  }

  // ---------------------------------------------------------------------------
  // File-system helpers
  // ---------------------------------------------------------------------------

  /// Returns the base directory for storing sticker images.
  ///
  /// Structure: `<appDocDir>/stickers/<packId>/`
  static Future<String> stickerDirectory(String packId) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/stickers/$packId';
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _persist(List<StickerPack> packs) async {
    final raw = packs.map((p) => p.toJsonString()).toList();
    await _prefs.setStringList(_packsKey, raw);
  }
}
