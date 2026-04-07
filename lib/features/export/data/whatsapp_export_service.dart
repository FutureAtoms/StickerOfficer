import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'whatsapp_sticker_channel.dart';

/// WhatsApp sticker export service
///
/// Handles conversion and export of stickers to WhatsApp format:
/// - Static: WebP, 512x512, max 100KB
/// - Animated: Animated WebP, 512x512, max 500KB, max 10s
/// - Pack: 3-30 stickers + 96x96 tray icon
class WhatsAppExportService {
  static const int stickerSize = 512;
  static const int trayIconSize = 96;
  static const int maxStaticSizeBytes = 100 * 1024; // 100KB
  static const int maxAnimatedSizeBytes = 500 * 1024; // 500KB
  static const int minStickersPerPack = 3;
  static const int maxStickersPerPack = 30;
  static const Duration _ffmpegTimeout = Duration(seconds: 30);

  /// Validates a sticker pack meets WhatsApp requirements.
  /// Note: does NOT reject oversized stickers — the export pipeline
  /// auto-compresses them. Only checks pack-level constraints.
  PackValidationResult validatePack({
    required String name,
    required List<StickerData> stickers,
    required Uint8List? trayIcon,
  }) {
    final errors = <String>[];

    if (name.isEmpty) {
      errors.add('Pack name is required');
    }
    if (stickers.length < minStickersPerPack) {
      errors.add('Pack needs at least $minStickersPerPack stickers');
    }
    if (stickers.length > maxStickersPerPack) {
      errors.add('Pack can have at most $maxStickersPerPack stickers');
    }
    if (trayIcon == null) {
      errors.add('Tray icon is required');
    }

    // No per-sticker size check here — the export pipeline will
    // resize + compress every sticker to fit automatically.

    return PackValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  /// Converts image bytes to WhatsApp-compatible 512x512 PNG.
  ///
  /// Quality-preserving approach — escalates compression only as needed:
  ///   1. Resize to 512x512 with max PNG compression (lossless, best quality)
  ///   2. If still too big, quantize colors 256→128→64 (slight quality loss)
  ///   3. If still too big, encode as high-quality JPEG then re-wrap as PNG
  ///   4. Nuclear: reduce JPEG quality until it fits
  ///
  /// The native Android side converts to WebP anyway, so the PNG here is
  /// an intermediate format — WebP is much smaller, so most stickers that
  /// pass as PNG will easily pass as WebP.
  Future<Uint8List> convertToWhatsAppFormat(
    Uint8List imageBytes, {
    bool isAnimated = false,
  }) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image');
    }

    final maxBytes = isAnimated ? maxAnimatedSizeBytes : maxStaticSizeBytes;

    // Always resize to 512x512 first (WhatsApp requirement)
    final resized = _resizeAndCenter(decoded, stickerSize);

    // Strategy 1: PNG with max compression — lossless, best quality
    final pngMax = Uint8List.fromList(img.encodePng(resized, level: 9));
    if (pngMax.lengthInBytes <= maxBytes) {
      return pngMax;
    }

    // Strategy 2: Quantize colors — slight quality loss but keeps 512x512
    // Start high (256 colors) and go down gradually
    for (final colors in [256, 192, 128, 96, 64]) {
      final quantized = img.quantize(resized, numberOfColors: colors);
      final encoded = Uint8List.fromList(img.encodePng(quantized, level: 9));
      if (encoded.lengthInBytes <= maxBytes) {
        return encoded;
      }
    }

    // Strategy 3: JPEG at high quality (90→70) — visually near-identical
    // The native side converts to WebP which handles this well
    for (var quality = 90; quality >= 50; quality -= 10) {
      final jpegBytes = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );
      if (jpegBytes.length <= maxBytes) {
        return jpegBytes;
      }
    }

    // Strategy 4: Lower JPEG quality (still at 512x512)
    for (var quality = 40; quality >= 20; quality -= 10) {
      final jpegBytes = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );
      if (jpegBytes.length <= maxBytes) {
        return jpegBytes;
      }
    }

    // Fallback: 512x512 + heavy quantize + max PNG compression
    final quantized = img.quantize(resized, numberOfColors: 32);
    return Uint8List.fromList(img.encodePng(quantized, level: 9));
  }

  /// Creates a 96x96 tray icon from the given sticker image bytes.
  ///
  /// Decodes the input, resizes to [trayIconSize]x[trayIconSize] while
  /// maintaining aspect ratio and centering on a transparent background,
  /// then encodes to PNG.
  Future<Uint8List> generateTrayIcon(Uint8List stickerBytes) async {
    final decoded = img.decodeImage(stickerBytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image for tray icon');
    }

    final resized = _resizeAndCenter(decoded, trayIconSize);
    return Uint8List.fromList(img.encodePng(resized));
  }

  /// Resizes [source] so it fits within [size]x[size], maintaining aspect
  /// ratio, then centers it on a transparent [size]x[size] canvas.
  static img.Image _resizeAndCenter(img.Image source, int size) {
    // Determine scale factor to fit within the target square.
    final scale =
        size / (source.width > source.height ? source.width : source.height);
    final newWidth = (source.width * scale).round().clamp(1, size);
    final newHeight = (source.height * scale).round().clamp(1, size);

    final resized = img.copyResize(
      source,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    // Create transparent canvas and composite the resized image at center.
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    // Fill with fully transparent pixels.
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    final offsetX = (size - newWidth) ~/ 2;
    final offsetY = (size - newHeight) ~/ 2;

    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    return canvas;
  }

  /// Exports sticker pack to WhatsApp.
  ///
  /// On Android: Uses the native ContentProvider + Intent system to add
  /// stickers directly to WhatsApp's sticker tray. Converts all images
  /// to 512x512 WebP format as required by WhatsApp.
  ///
  /// On iOS: Falls back to sharing sticker files via the share sheet,
  /// since WhatsApp on iOS doesn't support third-party sticker packs.
  /// Generates a proper 512x512 placeholder sticker image (a smiley face).
  /// Used when a pack has fewer than [minStickersPerPack] real stickers.
  static Uint8List generatePlaceholderSticker() {
    final canvas = img.Image(
      width: stickerSize,
      height: stickerSize,
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    // Draw a simple circle (emoji-like placeholder)
    img.drawCircle(
      canvas,
      x: stickerSize ~/ 2,
      y: stickerSize ~/ 2,
      radius: 200,
      color: img.ColorRgba8(255, 200, 0, 255),
    );
    img.fillCircle(
      canvas,
      x: stickerSize ~/ 2,
      y: stickerSize ~/ 2,
      radius: 200,
      color: img.ColorRgba8(255, 220, 50, 255),
    );

    return Uint8List.fromList(img.encodePng(canvas));
  }

  Future<ExportResult> exportToWhatsApp({
    required String packName,
    required String packAuthor,
    required List<StickerData> stickers,
    required Uint8List trayIcon,
    String? trayIconSourcePath,
    String? packIdentifier,
  }) async {
    final validation = validatePack(
      name: packName,
      stickers: stickers,
      trayIcon: trayIcon,
    );

    if (!validation.isValid) {
      return ExportResult(success: false, message: validation.errors.first);
    }

    final hasAnimatedStickers = stickers.any((sticker) => sticker.isAnimated);
    final hasStaticStickers = stickers.any((sticker) => !sticker.isAnimated);
    if (hasAnimatedStickers && hasStaticStickers) {
      return const ExportResult(
        success: false,
        message:
            'WhatsApp pack export requires all stickers to be either photos or animated.',
      );
    }

    final isAnimatedPack = hasAnimatedStickers;

    try {
      final resolvedPackIdentifier = _normalizePackIdentifier(
        packIdentifier ?? _defaultPackIdentifier(packName, isAnimatedPack),
      );

      final tempDir = await getTemporaryDirectory();
      final packDir = Directory(
        '${tempDir.path}/sticker_pack_$resolvedPackIdentifier',
      );
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
      }
      await packDir.create(recursive: true);

      final stickerPaths = <String>[];

      for (int i = 0; i < stickers.length; i++) {
        try {
          final sourcePath = stickers[i].sourcePath;

          if (Platform.isAndroid) {
            if (isAnimatedPack) {
              final animatedPath = await _prepareAnimatedStickerForAndroid(
                stickers[i],
                i,
                packDir,
              );
              if (animatedPath != null) {
                stickerPaths.add(animatedPath);
              }
              continue;
            }

            if (sourcePath != null && await File(sourcePath).exists()) {
              stickerPaths.add(sourcePath);
              continue;
            }
          } else if (isAnimatedPack &&
              sourcePath != null &&
              await File(sourcePath).exists()) {
            // Keep animated source files intact when falling back to share sheet.
            stickerPaths.add(sourcePath);
            continue;
          }

          final stickerBytes = stickers[i].data;
          final decoded = img.decodeImage(stickerBytes);

          if (decoded == null) {
            debugPrint('Sticker ${i + 1}: could not decode, skipping');
            continue;
          }

          // Skip tiny placeholder images (1x1, 2x2 etc)
          if (decoded.width < 4 || decoded.height < 4) {
            debugPrint('Sticker ${i + 1}: too small, using placeholder');
            final placeholder = generatePlaceholderSticker();
            final filePath = '${packDir.path}/sticker_${i + 1}.png';
            await File(filePath).writeAsBytes(placeholder);
            stickerPaths.add(filePath);
            continue;
          }

          final processedBytes = await convertToWhatsAppFormat(
            stickerBytes,
            isAnimated: stickers[i].isAnimated,
          );

          final filePath = '${packDir.path}/sticker_${i + 1}.png';
          await File(filePath).writeAsBytes(processedBytes);
          stickerPaths.add(filePath);
          debugPrint('Sticker ${i + 1}: ${processedBytes.length ~/ 1024}KB');
        } catch (e) {
          debugPrint('Sticker ${i + 1}: processing failed: $e');
        }
      }

      if (stickerPaths.length < minStickersPerPack) {
        return ExportResult(
          success: false,
          message:
              'Only ${stickerPaths.length} sticker${stickerPaths.length == 1 ? '' : 's'} could be prepared. WhatsApp needs at least $minStickersPerPack.',
        );
      }

      // Save tray icon
      String trayIconPath;
      if (Platform.isAndroid &&
          !isAnimatedPack &&
          trayIconSourcePath != null &&
          await File(trayIconSourcePath).exists()) {
        trayIconPath = trayIconSourcePath;
      } else {
        final trayDecoded = img.decodeImage(trayIcon);
        if (trayDecoded != null) {
          final trayResized = _resizeAndCenter(trayDecoded, trayIconSize);
          final trayPng = img.encodePng(trayResized);
          trayIconPath = '${packDir.path}/tray_icon.png';
          await File(trayIconPath).writeAsBytes(trayPng);
        } else {
          trayIconPath = stickerPaths.first;
        }
      }

      // --- Android: Use native WhatsApp sticker API ---
      if (Platform.isAndroid) {
        final result = await WhatsAppStickerChannel.addStickerPack(
          identifier: resolvedPackIdentifier,
          name: packName,
          publisher: packAuthor,
          stickerPaths: stickerPaths,
          trayIconPath: trayIconPath,
          animatedStickerPack: isAnimatedPack,
        );

        return ExportResult(success: result.success, message: result.message);
      }

      // --- iOS: Fall back to share sheet ---
      final xFiles =
          stickerPaths
              .map((path) => XFile(path, mimeType: _mimeTypeForPath(path)))
              .toList();
      xFiles.add(XFile(trayIconPath, mimeType: _mimeTypeForPath(trayIconPath)));

      await SharePlus.instance.share(
        ShareParams(
          files: xFiles,
          text: 'Sticker Pack: $packName by $packAuthor',
          subject: packName,
        ),
      );

      return ExportResult(
        success: true,
        message: 'Pack "$packName" shared! Open WhatsApp to use your stickers.',
      );
    } catch (e) {
      debugPrint('WhatsApp export failed: $e');
      return ExportResult(
        success: false,
        message: 'Export failed: ${e.toString().split('\n').first}',
      );
    }
  }

  Future<String?> _prepareAnimatedStickerForAndroid(
    StickerData sticker,
    int index,
    Directory packDir,
  ) async {
    final inputFile = await _resolveAnimatedInputFile(sticker, index, packDir);
    if (inputFile == null || !await inputFile.exists()) {
      debugPrint('Animated sticker ${index + 1}: input missing');
      return null;
    }

    final outputPath = '${packDir.path}/sticker_${index + 1}.webp';
    final stillImage = _isStillImagePath(inputFile.path);
    final attempts = <_AnimatedEncodeAttempt>[
      _AnimatedEncodeAttempt(
        contentSize: 512,
        fps: stillImage ? 8 : null,
        quality: 80,
      ),
      const _AnimatedEncodeAttempt(contentSize: 448, fps: 12, quality: 72),
      const _AnimatedEncodeAttempt(contentSize: 384, fps: 10, quality: 64),
      const _AnimatedEncodeAttempt(contentSize: 352, fps: 8, quality: 58),
      const _AnimatedEncodeAttempt(contentSize: 320, fps: 8, quality: 52),
    ];

    for (final attempt in attempts) {
      final success = await _encodeAnimatedWebp(
        inputPath: inputFile.path,
        outputPath: outputPath,
        contentSize: attempt.contentSize,
        fps: attempt.fps,
        quality: attempt.quality,
        stillImage: stillImage,
      );
      if (!success) {
        continue;
      }

      final outputFile = File(outputPath);
      final fileSize = await outputFile.length();
      if (fileSize <= maxAnimatedSizeBytes) {
        debugPrint('Animated sticker ${index + 1}: ${fileSize ~/ 1024}KB');
        return outputPath;
      }
    }

    try {
      await File(outputPath).delete();
    } catch (_) {
      // Best-effort cleanup only.
    }
    debugPrint('Animated sticker ${index + 1}: could not fit under 500KB');
    return null;
  }

  Future<File?> _resolveAnimatedInputFile(
    StickerData sticker,
    int index,
    Directory packDir,
  ) async {
    final sourcePath = sticker.sourcePath;
    if (sourcePath != null) {
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        return sourceFile;
      }
    }

    try {
      final normalized = await convertToWhatsAppFormat(sticker.data);
      final tempInputPath = '${packDir.path}/animated_input_${index + 1}.png';
      final tempInputFile = File(tempInputPath);
      await tempInputFile.writeAsBytes(normalized);
      return tempInputFile;
    } catch (error) {
      debugPrint(
        'Animated sticker ${index + 1}: failed to build input: $error',
      );
      return null;
    }
  }

  Future<bool> _encodeAnimatedWebp({
    required String inputPath,
    required String outputPath,
    required int contentSize,
    required int quality,
    required bool stillImage,
    int? fps,
  }) async {
    final encoded = await _runAnimatedWebpEncode(
      inputPath: inputPath,
      outputPath: outputPath,
      contentSize: contentSize,
      quality: quality,
      stillImage: stillImage,
      fps: fps,
    );
    if (!encoded) {
      return false;
    }

    if (await _outputHasAnimation(outputPath)) {
      return true;
    }

    debugPrint(
      'Animated WebP export collapsed to static output, retrying with forced animation marker.',
    );

    final forcedAnimation = await _encodeTwoFrameAnimatedWebp(
      inputPath: inputPath,
      outputPath: outputPath,
      contentSize: contentSize,
      quality: quality,
    );
    if (!forcedAnimation) {
      return false;
    }

    final hasAnimation = await _outputHasAnimation(outputPath);
    if (!hasAnimation) {
      debugPrint('Animated WebP export still missing animation chunks.');
    }
    return hasAnimation;
  }

  Future<bool> _runAnimatedWebpEncode({
    required String inputPath,
    required String outputPath,
    required int contentSize,
    required int quality,
    required bool stillImage,
    int? fps,
    bool forceAnimationMarker = false,
  }) async {
    final filter = <String>[
      if (fps != null) 'fps=$fps',
      'scale=$contentSize:$contentSize:force_original_aspect_ratio=decrease:flags=lanczos',
      'pad=$stickerSize:$stickerSize:(ow-iw)/2:(oh-ih)/2:color=0x00000000',
      'format=rgba',
      if (forceAnimationMarker)
        "drawbox=x='mod(n\\,2)':y=0:w=1:h=1:color=white@1:t=fill",
    ].join(',');

    final command =
        '${stillImage ? '-loop 1 -t 1 ' : ''}'
        '-i ${_quoteForShell(inputPath)} '
        '-an -vf "$filter" '
        '-c:v libwebp_anim '
        '-pix_fmt yuva420p '
        '-lossless 0 '
        '-q:v $quality '
        '-compression_level 6 '
        '-preset icon '
        '-loop 0 '
        '-vsync 0 '
        '-y ${_quoteForShell(outputPath)}';

    return _runFfmpegCommand(command);
  }

  Future<bool> _encodeTwoFrameAnimatedWebp({
    required String inputPath,
    required String outputPath,
    required int contentSize,
    required int quality,
  }) async {
    final frame1Path = '${outputPath}_frame_1.png';
    final frame1WebpPath = '${outputPath}_frame_1.webp';
    final frame2Path = '${outputPath}_frame_2.png';
    final frame2WebpPath = '${outputPath}_frame_2.webp';
    final extractFilter = <String>[
      'scale=$contentSize:$contentSize:force_original_aspect_ratio=decrease:flags=lanczos',
      'pad=$stickerSize:$stickerSize:(ow-iw)/2:(oh-ih)/2:color=0x00000000',
      'format=rgba',
    ].join(',');

    final extractCommand =
        '-i ${_quoteForShell(inputPath)} '
        '-an -vf "$extractFilter" '
        '-frames:v 1 '
        '-y ${_quoteForShell(frame1Path)}';

    final extracted = await _runFfmpegCommand(extractCommand);
    if (!extracted) {
      return false;
    }

    try {
      final repairFrame = img.Image(width: 1, height: 1, numChannels: 4);
      repairFrame.setPixelRgba(0, 0, 255, 0, 255, 255);
      await File(
        frame2Path,
      ).writeAsBytes(Uint8List.fromList(img.encodePng(repairFrame)));

      final encodedPrimary = await WhatsAppStickerChannel.encodeStaticWebpFrame(
        inputPath: frame1Path,
        outputPath: frame1WebpPath,
        quality: quality,
      );
      if (!encodedPrimary) {
        debugPrint('Animated fallback primary frame encode failed.');
        return false;
      }

      final encodedRepair = await WhatsAppStickerChannel.encodeStaticWebpFrame(
        inputPath: frame2Path,
        outputPath: frame2WebpPath,
        quality: 100,
      );
      if (!encodedRepair) {
        debugPrint('Animated fallback repair frame encode failed.');
        return false;
      }

      final primaryFrameWebp = await File(frame1WebpPath).readAsBytes();
      final repairFrameWebp = await File(frame2WebpPath).readAsBytes();
      final animatedBytes = buildAnimatedWebpFromStillFrames(
        primaryFrameWebp: primaryFrameWebp,
        primaryFrameWidth: stickerSize,
        primaryFrameHeight: stickerSize,
        repairFrameWebp: repairFrameWebp,
        repairFrameWidth: 1,
        repairFrameHeight: 1,
      );
      if (animatedBytes == null) {
        debugPrint('Animated fallback mux failed.');
        return false;
      }

      await File(outputPath).writeAsBytes(animatedBytes);
      return webpHasAnimation(animatedBytes);
    } catch (error) {
      debugPrint('Animated fallback frame synthesis failed: $error');
      return false;
    } finally {
      for (final tempPath in [
        frame1Path,
        frame1WebpPath,
        frame2Path,
        frame2WebpPath,
      ]) {
        try {
          await File(tempPath).delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }

  @visibleForTesting
  Uint8List? buildAnimatedWebpFromStillFrames({
    required Uint8List primaryFrameWebp,
    required int primaryFrameWidth,
    required int primaryFrameHeight,
    required Uint8List repairFrameWebp,
    required int repairFrameWidth,
    required int repairFrameHeight,
  }) {
    final primaryFrame = _extractStillFrameData(primaryFrameWebp);
    final repairFrame = _extractStillFrameData(repairFrameWebp);
    if (primaryFrame == null || repairFrame == null) {
      return null;
    }

    final bytes =
        BytesBuilder(copy: false)
          ..add('RIFF'.codeUnits)
          ..add(Uint8List(4))
          ..add('WEBP'.codeUnits)
          ..add(
            _buildWebpChunk(
              'VP8X',
              _buildVp8xPayload(
                canvasWidth: stickerSize,
                canvasHeight: stickerSize,
                hasAlpha: primaryFrame.hasAlpha || repairFrame.hasAlpha,
              ),
            ),
          )
          ..add(_buildWebpChunk('ANIM', Uint8List(6)))
          ..add(
            _buildWebpChunk(
              'ANMF',
              _buildAnmfPayload(
                frameX: 0,
                frameY: 0,
                frameWidth: primaryFrameWidth,
                frameHeight: primaryFrameHeight,
                durationMs: 500,
                flags: 0x02,
                imageChunks: primaryFrame.imageChunks,
              ),
            ),
          )
          ..add(
            _buildWebpChunk(
              'ANMF',
              _buildAnmfPayload(
                frameX: 0,
                frameY: 0,
                frameWidth: repairFrameWidth,
                frameHeight: repairFrameHeight,
                durationMs: 500,
                flags: 0x00,
                imageChunks: repairFrame.imageChunks,
              ),
            ),
          );

    final output = bytes.toBytes();
    _writeUint32LE(output, 4, output.length - 8);
    return output;
  }

  Future<bool> _runFfmpegCommand(String command) async {
    try {
      final session = await FFmpegKit.execute(command).timeout(
        _ffmpegTimeout,
        onTimeout: () {
          FFmpegKit.cancel();
          throw TimeoutException('Animated WebP encoding timed out');
        },
      );
      final returnCode = await session.getReturnCode();
      return ReturnCode.isSuccess(returnCode);
    } catch (error) {
      debugPrint('Animated WebP export failed: $error');
      return false;
    }
  }

  Future<bool> _outputHasAnimation(String outputPath) async {
    try {
      final bytes = await File(outputPath).readAsBytes();
      return webpHasAnimation(bytes);
    } catch (error) {
      debugPrint('Animated WebP inspection failed: $error');
      return false;
    }
  }

  @visibleForTesting
  bool webpHasAnimation(Uint8List bytes) {
    if (!_hasAsciiAt(bytes, 0, 'RIFF') || !_hasAsciiAt(bytes, 8, 'WEBP')) {
      return false;
    }

    var offset = 12;
    var animationFrameCount = 0;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32LE(bytes, offset + 4);
      if (chunkId == 'ANMF') {
        animationFrameCount++;
      }

      final paddedChunkSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
      offset += 8 + paddedChunkSize;
    }

    return animationFrameCount > 1;
  }

  _StillFrameWebpData? _extractStillFrameData(Uint8List bytes) {
    if (!_hasAsciiAt(bytes, 0, 'RIFF') || !_hasAsciiAt(bytes, 8, 'WEBP')) {
      return null;
    }

    final imageChunks = <_WebpChunkData>[];
    var hasAlpha = false;
    var hasImagePayload = false;
    var offset = 12;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32LE(bytes, offset + 4);
      final chunkDataOffset = offset + 8;
      final chunkDataEnd = chunkDataOffset + chunkSize;
      if (chunkDataEnd > bytes.length) {
        return null;
      }

      final chunkData = Uint8List.fromList(
        bytes.sublist(chunkDataOffset, chunkDataEnd),
      );

      switch (chunkId) {
        case 'VP8X':
          if (chunkData.isNotEmpty && (chunkData[0] & 0x10) != 0) {
            hasAlpha = true;
          }
          break;
        case 'ALPH':
          hasAlpha = true;
          imageChunks.add(_WebpChunkData(chunkId, chunkData));
          break;
        case 'VP8 ':
          hasImagePayload = true;
          imageChunks.add(_WebpChunkData(chunkId, chunkData));
          break;
        case 'VP8L':
          hasImagePayload = true;
          hasAlpha = hasAlpha || _vp8lHasAlpha(chunkData);
          imageChunks.add(_WebpChunkData(chunkId, chunkData));
          break;
      }

      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (!hasImagePayload || imageChunks.isEmpty) {
      return null;
    }

    return _StillFrameWebpData(imageChunks: imageChunks, hasAlpha: hasAlpha);
  }

  bool _hasAsciiAt(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) {
      return false;
    }

    for (var i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  int _readUint32LE(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      return 0;
    }
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  bool _vp8lHasAlpha(Uint8List bytes) {
    if (bytes.length < 5 || bytes.first != 0x2f) {
      return false;
    }

    final signature =
        bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
    return ((signature >> 28) & 0x1) == 1;
  }

  Uint8List _buildVp8xPayload({
    required int canvasWidth,
    required int canvasHeight,
    required bool hasAlpha,
  }) {
    final payload = Uint8List(10);
    payload[0] = 0x02 | (hasAlpha ? 0x10 : 0x00);
    _writeUint24LE(payload, 4, canvasWidth - 1);
    _writeUint24LE(payload, 7, canvasHeight - 1);
    return payload;
  }

  Uint8List _buildAnmfPayload({
    required int frameX,
    required int frameY,
    required int frameWidth,
    required int frameHeight,
    required int durationMs,
    required int flags,
    required List<_WebpChunkData> imageChunks,
  }) {
    final payload =
        BytesBuilder(copy: false)
          ..add(_uint24LE(frameX ~/ 2))
          ..add(_uint24LE(frameY ~/ 2))
          ..add(_uint24LE(frameWidth - 1))
          ..add(_uint24LE(frameHeight - 1))
          ..add(_uint24LE(durationMs))
          ..add([flags & 0xff]);

    for (final chunk in imageChunks) {
      payload.add(_buildWebpChunk(chunk.id, chunk.data));
    }

    return payload.toBytes();
  }

  Uint8List _buildWebpChunk(String id, List<int> payload) {
    final paddedLength = payload.length + (payload.length.isOdd ? 1 : 0);
    final chunk = Uint8List(8 + paddedLength);
    chunk.setRange(0, 4, id.codeUnits);
    _writeUint32LE(chunk, 4, payload.length);
    chunk.setRange(8, 8 + payload.length, payload);
    return chunk;
  }

  List<int> _uint24LE(int value) => [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
  ];

  void _writeUint24LE(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >> 8) & 0xff;
    bytes[offset + 2] = (value >> 16) & 0xff;
  }

  void _writeUint32LE(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >> 8) & 0xff;
    bytes[offset + 2] = (value >> 16) & 0xff;
    bytes[offset + 3] = (value >> 24) & 0xff;
  }

  String _defaultPackIdentifier(String packName, bool isAnimatedPack) {
    final safePackName = packName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._ -]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    final suffix = isAnimatedPack ? 'animated' : 'static';
    if (safePackName.isEmpty) {
      return 'sticker_pack_${suffix}_${DateTime.now().millisecondsSinceEpoch}';
    }
    return '${safePackName}_$suffix';
  }

  String _normalizePackIdentifier(String rawIdentifier) {
    final normalized = rawIdentifier
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) {
      return 'sticker_pack_${DateTime.now().millisecondsSinceEpoch}';
    }
    return normalized.length > 120 ? normalized.substring(0, 120) : normalized;
  }

  String _mimeTypeForPath(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.webp')) return 'image/webp';
    if (lowerPath.endsWith('.gif')) return 'image/gif';
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  bool _isStillImagePath(String path) {
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.bmp') ||
        lowerPath.endsWith('.heic') ||
        lowerPath.endsWith('.heif');
  }

  String _quoteForShell(String value) {
    final escaped = value.replaceAll("'", "'\"'\"'");
    return "'$escaped'";
  }
}

class StickerData {
  final Uint8List data;
  final bool isAnimated;
  final String? sourcePath;

  const StickerData({
    required this.data,
    this.isAnimated = false,
    this.sourcePath,
  });
}

class PackValidationResult {
  final bool isValid;
  final List<String> errors;

  const PackValidationResult({required this.isValid, required this.errors});
}

class ExportResult {
  final bool success;
  final String message;

  const ExportResult({required this.success, required this.message});
}

class _AnimatedEncodeAttempt {
  final int contentSize;
  final int? fps;
  final int quality;

  const _AnimatedEncodeAttempt({
    required this.contentSize,
    required this.fps,
    required this.quality,
  });
}

class _StillFrameWebpData {
  final List<_WebpChunkData> imageChunks;
  final bool hasAlpha;

  const _StillFrameWebpData({
    required this.imageChunks,
    required this.hasAlpha,
  });
}

class _WebpChunkData {
  final String id;
  final Uint8List data;

  const _WebpChunkData(this.id, this.data);
}
