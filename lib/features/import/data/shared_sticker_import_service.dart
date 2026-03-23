import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../../data/models/sticker_pack.dart';
import '../../../data/repositories/pack_repository.dart';
import 'shared_sticker_import_channel.dart';

class SharedStickerImportService {
  final Uuid _uuid;

  SharedStickerImportService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  Future<StickerPack> importFiles(
    List<SharedStickerImportFile> files, {
    String? baseDirectory,
  }) async {
    final validFiles = <_PreparedImportFile>[];

    for (final file in files) {
      final source = File(file.path);
      if (!await source.exists()) {
        continue;
      }

      final bytes = await source.readAsBytes();
      if (img.decodeImage(bytes) == null) {
        continue;
      }

      validFiles.add(
        _PreparedImportFile(
          source: source,
          bytes: bytes,
          extension: _preferredExtension(file, source.path),
        ),
      );
    }

    if (validFiles.isEmpty) {
      throw const SharedStickerImportException(
        'No valid sticker images were shared.',
      );
    }

    final packId = _uuid.v4();
    final packDirPath =
        baseDirectory ?? await PackRepository.stickerDirectory(packId);
    final packDir = Directory(packDirPath);
    await packDir.create(recursive: true);

    final stickerPaths = <String>[];
    for (var i = 0; i < validFiles.length; i++) {
      final imported = validFiles[i];
      final destination = File(
        '${packDir.path}/sticker_${i + 1}.${imported.extension}',
      );
      await destination.writeAsBytes(imported.bytes, flush: true);
      stickerPaths.add(destination.path);
    }

    final firstName = files.first.name ?? validFiles.first.source.uri.pathSegments.last;
    final packName = _derivePackName(firstName, stickerPaths.length);

    return StickerPack(
      id: packId,
      name: packName,
      authorName: 'Imported',
      stickerPaths: stickerPaths,
      trayIconPath: stickerPaths.first,
      createdAt: DateTime.now(),
      isPublic: false,
      tags: const ['imported', 'shared'],
    );
  }

  static String _preferredExtension(
    SharedStickerImportFile file,
    String fallbackPath,
  ) {
    final normalizedMime = file.mimeType?.toLowerCase();
    if (normalizedMime == 'image/webp') {
      return 'webp';
    }
    if (normalizedMime == 'image/png') {
      return 'png';
    }
    if (normalizedMime == 'image/jpeg' || normalizedMime == 'image/jpg') {
      return 'jpg';
    }

    final candidate = file.name ?? fallbackPath;
    final dotIndex = candidate.lastIndexOf('.');
    if (dotIndex > -1 && dotIndex < candidate.length - 1) {
      final extension = candidate.substring(dotIndex + 1).toLowerCase();
      if (extension == 'webp' ||
          extension == 'png' ||
          extension == 'jpg' ||
          extension == 'jpeg') {
        return extension == 'jpeg' ? 'jpg' : extension;
      }
    }

    return 'png';
  }

  static String _derivePackName(String sourceName, int count) {
    final cleaned = sourceName
        .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (count == 1 && cleaned.isNotEmpty) {
      return cleaned.length > 48 ? cleaned.substring(0, 48).trim() : cleaned;
    }

    final stamp = DateTime.now();
    final dateLabel =
        '${stamp.year}-${stamp.month.toString().padLeft(2, '0')}-${stamp.day.toString().padLeft(2, '0')}';
    return 'Imported Pack $dateLabel';
  }
}

class SharedStickerImportException implements Exception {
  final String message;

  const SharedStickerImportException(this.message);

  @override
  String toString() => message;
}

class _PreparedImportFile {
  final File source;
  final List<int> bytes;
  final String extension;

  const _PreparedImportFile({
    required this.source,
    required this.bytes,
    required this.extension,
  });
}
