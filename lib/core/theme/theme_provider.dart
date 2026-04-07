import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers.dart';
import 'sticker_themes.dart';

// =============================================================================
// Persisted theme selection provider
// =============================================================================

const _prefsKey = 'selected_theme';

final stickerThemeProvider =
    StateNotifierProvider<StickerThemeNotifier, StickerThemeData>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return StickerThemeNotifier(prefs);
    });

class StickerThemeNotifier extends StateNotifier<StickerThemeData> {
  final SharedPreferences _prefs;

  StickerThemeNotifier(this._prefs) : super(_loadSaved(_prefs));

  static StickerThemeData _loadSaved(SharedPreferences prefs) {
    final key = prefs.getString(_prefsKey);
    if (key == null) return StickerThemes.bubblegum;
    return StickerThemes.fromKey(key);
  }

  /// Select a new theme. Persists to SharedPreferences immediately.
  void select(StickerThemeType type) {
    final theme = StickerThemes.fromType(type);
    state = theme;
    _prefs.setString(_prefsKey, type.name);
  }

  /// Current theme type.
  StickerThemeType get currentType => state.type;
}
