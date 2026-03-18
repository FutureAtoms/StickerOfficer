import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for consistent sticker editing
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // TODO: Initialize Firebase when configured
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const ProviderScope(child: StickerOfficerApp()));
}
