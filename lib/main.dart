import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'data/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for consistent sticker editing
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize local storage
  final prefs = await SharedPreferences.getInstance();

  // TODO: Initialize Firebase when configured
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const StickerOfficerApp(),
    ),
  );
}
