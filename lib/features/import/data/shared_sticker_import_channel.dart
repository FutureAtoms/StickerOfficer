import 'package:flutter/services.dart';

class SharedStickerImportFile {
  final String path;
  final String? mimeType;
  final String? name;

  const SharedStickerImportFile({
    required this.path,
    this.mimeType,
    this.name,
  });

  factory SharedStickerImportFile.fromMap(Map<Object?, Object?> map) {
    return SharedStickerImportFile(
      path: map['path'] as String,
      mimeType: map['mimeType'] as String?,
      name: map['name'] as String?,
    );
  }
}

class SharedStickerImportChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.futureatoms.sticker_officer/share_import',
  );

  static Future<List<SharedStickerImportFile>> getPendingFiles() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      'getPendingSharedMedia',
    );
    return _decode(raw);
  }

  static Future<void> setListener(
    Future<void> Function(List<SharedStickerImportFile> files) onFiles,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedMediaReceived') {
        return;
      }

      final files = _decode(call.arguments as List<Object?>?);
      if (files.isEmpty) {
        return;
      }
      await onFiles(files);
    });
  }

  static void clearListener() {
    _channel.setMethodCallHandler(null);
  }

  static List<SharedStickerImportFile> _decode(List<Object?>? raw) {
    if (raw == null) {
      return const [];
    }

    return raw
        .whereType<Map<Object?, Object?>>()
        .map(SharedStickerImportFile.fromMap)
        .where((file) => file.path.isNotEmpty)
        .toList(growable: false);
  }
}
