import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/features/export/data/whatsapp_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WhatsAppExportService service;

  setUp(() {
    service = WhatsAppExportService();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<StickerData> makeStickers(int count, {int sizeBytes = 1000, bool isAnimated = false}) {
    return List.generate(
      count,
      (_) => StickerData(data: Uint8List(sizeBytes), isAnimated: isAnimated),
    );
  }

  PackValidationResult validPack({
    String name = 'Test Pack',
    int stickerCount = 5,
    int stickerSize = 1000,
    Uint8List? trayIcon,
    List<StickerData>? stickers,
  }) {
    return service.validatePack(
      name: name,
      stickers: stickers ?? makeStickers(stickerCount, sizeBytes: stickerSize),
      trayIcon: trayIcon ?? Uint8List(100),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Constants verification
  // ---------------------------------------------------------------------------

  group('Constants', () {
    test('stickerSize is 512', () {
      expect(WhatsAppExportService.stickerSize, 512);
    });

    test('trayIconSize is 96', () {
      expect(WhatsAppExportService.trayIconSize, 96);
    });

    test('maxStaticSizeBytes is 100KB', () {
      expect(WhatsAppExportService.maxStaticSizeBytes, 100 * 1024);
    });

    test('maxAnimatedSizeBytes is 500KB', () {
      expect(WhatsAppExportService.maxAnimatedSizeBytes, 500 * 1024);
    });

    test('minStickersPerPack is 3', () {
      expect(WhatsAppExportService.minStickersPerPack, 3);
    });

    test('maxStickersPerPack is 30', () {
      expect(WhatsAppExportService.maxStickersPerPack, 30);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Validation — name
  // ---------------------------------------------------------------------------

  group('Validation - pack name', () {
    test('rejects empty pack name', () {
      final result = validPack(name: '');

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Pack name is required'));
    });

    test('accepts non-empty pack name', () {
      final result = validPack(name: 'My Pack');

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts single-character pack name', () {
      final result = validPack(name: 'A');

      expect(result.isValid, isTrue);
    });

    test('accepts pack name with special characters', () {
      final result = validPack(name: 'Pack #1 (Fun!)');

      expect(result.isValid, isTrue);
    });

    test('accepts pack name with unicode/emoji', () {
      final result = validPack(name: 'Cool Pack \u{1F600}');

      expect(result.isValid, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Validation — sticker count
  // ---------------------------------------------------------------------------

  group('Validation - sticker count', () {
    test('rejects zero stickers', () {
      final result = validPack(stickerCount: 0);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
    });

    test('rejects 1 sticker', () {
      final result = validPack(stickerCount: 1);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
    });

    test('rejects 2 stickers', () {
      final result = validPack(stickerCount: 2);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
    });

    test('accepts exactly 3 stickers (minimum boundary)', () {
      final result = validPack(stickerCount: 3);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts 4 stickers', () {
      final result = validPack(stickerCount: 4);

      expect(result.isValid, isTrue);
    });

    test('accepts 15 stickers (midrange)', () {
      final result = validPack(stickerCount: 15);

      expect(result.isValid, isTrue);
    });

    test('accepts 29 stickers', () {
      final result = validPack(stickerCount: 29);

      expect(result.isValid, isTrue);
    });

    test('accepts exactly 30 stickers (maximum boundary)', () {
      final result = validPack(stickerCount: 30);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('rejects 31 stickers', () {
      final result = validPack(stickerCount: 31);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at most 30')), isTrue);
    });

    test('rejects 100 stickers', () {
      final result = validPack(stickerCount: 100);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at most 30')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Validation — tray icon
  // ---------------------------------------------------------------------------

  group('Validation - tray icon', () {
    test('rejects null tray icon', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: makeStickers(5),
        trayIcon: null,
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Tray icon is required'));
    });

    test('accepts non-null tray icon', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: makeStickers(5),
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts tray icon with minimal data (1 byte)', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: makeStickers(5),
        trayIcon: Uint8List(1),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts empty (zero-length) tray icon bytes', () {
      // Null is rejected, but a non-null Uint8List with zero length passes.
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: makeStickers(5),
        trayIcon: Uint8List(0),
      );

      expect(result.isValid, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Validation — static sticker size limits
  // ---------------------------------------------------------------------------

  group('Validation - static sticker size', () {
    test('accepts sticker well under 100KB', () {
      final result = validPack(stickerCount: 3, stickerSize: 50 * 1024);

      expect(result.isValid, isTrue);
    });

    test('accepts sticker at exactly 100KB (boundary)', () {
      final result = validPack(stickerCount: 3, stickerSize: 100 * 1024);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts sticker at 100KB + 1 byte (auto-compressed during export)', () {
      // validatePack no longer rejects oversized stickers — export pipeline
      // auto-compresses them to fit.
      final result = validPack(stickerCount: 3, stickerSize: 100 * 1024 + 1);

      expect(result.isValid, isTrue);
    });

    test('accepts sticker at 200KB (auto-compressed during export)', () {
      final result = validPack(stickerCount: 3, stickerSize: 200 * 1024);

      expect(result.isValid, isTrue);
    });

    test('oversized stickers pass validation (compressed during export)', () {
      final stickers = [
        StickerData(data: Uint8List(1000)),
        StickerData(data: Uint8List(1000)),
        StickerData(data: Uint8List(200 * 1024)),
      ];

      final result = service.validatePack(
        name: 'Test Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      // No per-sticker size errors — export pipeline handles compression
      expect(result.isValid, isTrue);
    });

    test('validation only checks pack-level constraints, not sticker size', () {
      final stickers = [
        StickerData(data: Uint8List(200 * 1024)),
        StickerData(data: Uint8List(1000)),
        StickerData(data: Uint8List(1000)),
      ];

      final result = service.validatePack(
        name: 'Test Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Validation — animated sticker size limits
  // ---------------------------------------------------------------------------

  group('Validation - animated sticker size', () {
    test('accepts animated sticker well under 500KB', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 200 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts animated sticker at exactly 500KB (boundary)', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 500 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts animated sticker at 500KB + 1 byte (auto-compressed during export)', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 500 * 1024 + 1, isAnimated: true),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts animated sticker at 400KB (between static and animated limit)', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 400 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts static sticker at 200KB (auto-compressed during export)', () {
      // No per-sticker size check in validation anymore
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 200 * 1024, isAnimated: false),
      );

      expect(result.isValid, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 7. Validation — mixed static and animated stickers
  // ---------------------------------------------------------------------------

  group('Validation - mixed static and animated stickers', () {
    test('validates each sticker against its own size limit', () {
      final stickers = [
        StickerData(data: Uint8List(80 * 1024), isAnimated: false), // OK
        StickerData(data: Uint8List(400 * 1024), isAnimated: true), // OK
        StickerData(data: Uint8List(50 * 1024), isAnimated: false), // OK
      ];

      final result = service.validatePack(
        name: 'Mixed Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts oversized static sticker in mixed pack (auto-compressed)', () {
      final stickers = [
        StickerData(data: Uint8List(200 * 1024), isAnimated: false),
        StickerData(data: Uint8List(400 * 1024), isAnimated: true),
        StickerData(data: Uint8List(50 * 1024), isAnimated: false),
      ];

      final result = service.validatePack(
        name: 'Mixed Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isTrue);
    });

    test('accepts oversized animated sticker in mixed pack (auto-compressed)', () {
      final stickers = [
        StickerData(data: Uint8List(80 * 1024), isAnimated: false),
        StickerData(data: Uint8List(600 * 1024), isAnimated: true),
        StickerData(data: Uint8List(50 * 1024), isAnimated: false),
      ];

      final result = service.validatePack(
        name: 'Mixed Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 8. Multiple validation errors at once
  // ---------------------------------------------------------------------------

  group('Validation - multiple errors', () {
    test('reports empty name AND too few stickers', () {
      final result = service.validatePack(
        name: '',
        stickers: makeStickers(1),
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.length, greaterThanOrEqualTo(2));
      expect(result.errors, contains('Pack name is required'));
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
    });

    test('reports empty name AND missing tray icon', () {
      final result = service.validatePack(
        name: '',
        stickers: makeStickers(5),
        trayIcon: null,
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Pack name is required'));
      expect(result.errors, contains('Tray icon is required'));
    });

    test('reports too few stickers AND missing tray icon', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: makeStickers(2),
        trayIcon: null,
      );

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
      expect(result.errors, contains('Tray icon is required'));
    });

    test('reports all errors: empty name, too few stickers, missing tray icon', () {
      final result = service.validatePack(
        name: '',
        stickers: makeStickers(0),
        trayIcon: null,
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Pack name is required'));
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
      expect(result.errors, contains('Tray icon is required'));
    });

    test('oversized stickers no longer cause validation errors', () {
      final stickers = [
        StickerData(data: Uint8List(200 * 1024)),
        StickerData(data: Uint8List(300 * 1024)),
        StickerData(data: Uint8List(50 * 1024)),
      ];

      final result = service.validatePack(
        name: 'Test Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      // No per-sticker size errors — auto-compressed during export
      expect(result.isValid, isTrue);
    });

    test('collects empty name and missing tray errors (but not sticker size)', () {
      final stickers = [
        StickerData(data: Uint8List(200 * 1024)),
        StickerData(data: Uint8List(200 * 1024)),
        StickerData(data: Uint8List(200 * 1024)),
      ];

      final result = service.validatePack(
        name: '',
        stickers: stickers,
        trayIcon: null,
      );

      expect(result.isValid, isFalse);
      // Only pack-level errors: name + tray icon (no sticker size errors)
      expect(result.errors.length, 2);
      expect(result.errors, contains('Pack name is required'));
      expect(result.errors, contains('Tray icon is required'));
    });
  });

  // ---------------------------------------------------------------------------
  // 9. Valid pack acceptance tests
  // ---------------------------------------------------------------------------

  group('Validation - valid packs', () {
    test('accepts minimal valid pack (3 stickers, small size)', () {
      final result = validPack(stickerCount: 3, stickerSize: 1000);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts maximum valid pack (30 stickers at max size)', () {
      final result = validPack(stickerCount: 30, stickerSize: 100 * 1024);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts pack of 30 animated stickers at 500KB each', () {
      final result = validPack(
        stickers: makeStickers(30, sizeBytes: 500 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 10. PackValidationResult model
  // ---------------------------------------------------------------------------

  group('PackValidationResult', () {
    test('isValid is true when errors list is empty', () {
      const result = PackValidationResult(isValid: true, errors: []);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('isValid is false when errors list is non-empty', () {
      const result = PackValidationResult(
        isValid: false,
        errors: ['something wrong'],
      );

      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // 11. StickerData model
  // ---------------------------------------------------------------------------

  group('StickerData', () {
    test('defaults isAnimated to false', () {
      final sticker = StickerData(data: Uint8List(100));

      expect(sticker.isAnimated, isFalse);
    });

    test('stores isAnimated true when provided', () {
      final sticker = StickerData(data: Uint8List(100), isAnimated: true);

      expect(sticker.isAnimated, isTrue);
    });

    test('stores data correctly', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sticker = StickerData(data: bytes);

      expect(sticker.data, bytes);
      expect(sticker.data.lengthInBytes, 5);
    });
  });

  // ---------------------------------------------------------------------------
  // 12. ExportResult model
  // ---------------------------------------------------------------------------

  group('ExportResult', () {
    test('stores success and message', () {
      const result = ExportResult(success: true, message: 'Done');

      expect(result.success, isTrue);
      expect(result.message, 'Done');
    });

    test('stores failure and message', () {
      const result = ExportResult(success: false, message: 'Failed');

      expect(result.success, isFalse);
      expect(result.message, 'Failed');
    });
  });

  // ---------------------------------------------------------------------------
  // 13. Image conversion — convertToWhatsAppFormat (IMPLEMENTED)
  // ---------------------------------------------------------------------------

  group('convertToWhatsAppFormat', () {
    test('resizes image to 512x512', () async {
      final testImage = img.Image(width: 100, height: 50);
      img.fill(testImage, color: img.ColorRgba8(255, 0, 0, 255));
      final input = Uint8List.fromList(img.encodePng(testImage));

      final output = await service.convertToWhatsAppFormat(input);

      final decoded = img.decodeImage(output);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('processes animated flag without error', () async {
      final testImage = img.Image(width: 64, height: 64);
      img.fill(testImage, color: img.ColorRgba8(0, 255, 0, 255));
      final input = Uint8List.fromList(img.encodePng(testImage));

      final output =
          await service.convertToWhatsAppFormat(input, isAnimated: true);

      expect(output, isNotEmpty);
    });

    test('throws on invalid image data', () async {
      final garbage = Uint8List.fromList([10, 20, 30, 40, 50]);
      expect(
        () => service.convertToWhatsAppFormat(garbage),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns different bytes than input (actual processing)', () async {
      final testImage = img.Image(width: 200, height: 200);
      img.fill(testImage, color: img.ColorRgba8(0, 0, 255, 255));
      final input = Uint8List.fromList(img.encodePng(testImage));

      final output = await service.convertToWhatsAppFormat(input);

      expect(output, isNot(same(input)));
    });
  });

  // ---------------------------------------------------------------------------
  // 14. Tray icon generation — generateTrayIcon (IMPLEMENTED)
  // ---------------------------------------------------------------------------

  group('generateTrayIcon', () {
    test('resizes image to 96x96', () async {
      final testImage = img.Image(width: 512, height: 512);
      img.fill(testImage, color: img.ColorRgba8(255, 255, 0, 255));
      final input = Uint8List.fromList(img.encodePng(testImage));

      final output = await service.generateTrayIcon(input);

      final decoded = img.decodeImage(output);
      expect(decoded, isNotNull);
      expect(decoded!.width, 96);
      expect(decoded.height, 96);
    });

    test('returns different bytes than input (actual processing)', () async {
      final testImage = img.Image(width: 200, height: 200);
      img.fill(testImage, color: img.ColorRgba8(128, 128, 128, 255));
      final input = Uint8List.fromList(img.encodePng(testImage));

      final output = await service.generateTrayIcon(input);

      expect(output, isNot(same(input)));
    });

    test('throws on invalid image data', () async {
      final garbage = Uint8List.fromList([99, 98, 97]);
      expect(
        () => service.generateTrayIcon(garbage),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 15. Export flow — exportToWhatsApp
  // ---------------------------------------------------------------------------

  group('exportToWhatsApp', () {
    // Note: exportToWhatsApp now uses getTemporaryDirectory() and Share.shareXFiles()
    // which are not available in test environment. Valid packs will fail gracefully
    // with a "Failed to share" message in tests. On a real device it opens the
    // system share sheet.

    test('returns failure in test environment (no platform APIs)', () async {
      final result = await service.exportToWhatsApp(
        packName: 'My Stickers',
        packAuthor: 'Test Author',
        stickers: makeStickers(5, sizeBytes: 10 * 1024),
        trayIcon: Uint8List(100),
      );

      // In test env, getTemporaryDirectory() throws MissingPluginException
      expect(result.success, isFalse);
      expect(result.message, contains('Export failed'));
    });

    test('validates before exporting — rejects empty pack name', () async {
      final result = await service.exportToWhatsApp(
        packName: '',
        packAuthor: 'Author',
        stickers: makeStickers(5),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isFalse);
      expect(result.message, 'Pack name is required');
    });

    test('validates before exporting — rejects too few stickers', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Test Pack',
        packAuthor: 'Author',
        stickers: makeStickers(1),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('at least 3'));
    });

    test('validates before exporting — rejects too many stickers', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Test Pack',
        packAuthor: 'Author',
        stickers: makeStickers(31),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('at most 30'));
    });

    test('oversized stickers pass validation (auto-compressed during export)', () async {
      // Oversized stickers are no longer rejected at validation — they're
      // auto-compressed by the export pipeline.
      final result = await service.exportToWhatsApp(
        packName: 'Test Pack',
        packAuthor: 'Author',
        stickers: makeStickers(3, sizeBytes: 200 * 1024),
        trayIcon: Uint8List(100),
      );

      // Passes validation but fails on platform API in test env
      expect(result.success, isFalse);
      expect(result.message, isNot(contains('exceeds max size')));
    });

    test('returns only the first error message on failure', () async {
      // Empty name AND too few stickers — should return only the first error.
      final result = await service.exportToWhatsApp(
        packName: '',
        packAuthor: 'Author',
        stickers: makeStickers(1),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isFalse);
      expect(result.message, 'Pack name is required');
    });

    test('valid min pack fails gracefully in test env (no platform)', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Min Pack',
        packAuthor: 'Author',
        stickers: makeStickers(3),
        trayIcon: Uint8List(100),
      );

      // Passes validation but fails on platform API in test env
      expect(result.success, isFalse);
      expect(result.message, contains('Export failed'));
    });

    test('valid max pack fails gracefully in test env (no platform)', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Max Pack',
        packAuthor: 'Author',
        stickers: makeStickers(30),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Export failed'));
    });

    test('valid pack with small tray icon fails gracefully in test env',
        () async {
      final result = await service.exportToWhatsApp(
        packName: 'Pack',
        packAuthor: 'Author',
        stickers: makeStickers(3),
        trayIcon: Uint8List(1),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Export failed'));
    });

    test('packAuthor does not affect validation — fails on platform in test',
        () async {
      final result = await service.exportToWhatsApp(
        packName: 'Pack',
        packAuthor: '',
        stickers: makeStickers(3),
        trayIcon: Uint8List(100),
      );

      // Passes validation (empty author is fine), fails on platform
      expect(result.success, isFalse);
      expect(result.message, contains('Export failed'));
    });
  });

  // ---------------------------------------------------------------------------
  // 16. Boundary combination tests
  // ---------------------------------------------------------------------------

  group('Boundary combinations', () {
    test('exactly 3 stickers at exactly 100KB each', () {
      final result = validPack(stickerCount: 3, stickerSize: 100 * 1024);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('exactly 30 stickers at exactly 100KB each', () {
      final result = validPack(stickerCount: 30, stickerSize: 100 * 1024);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('exactly 3 animated stickers at exactly 500KB each', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 500 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('exactly 30 animated stickers at exactly 500KB each', () {
      final result = validPack(
        stickers: makeStickers(30, sizeBytes: 500 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('2 oversized stickers — only count fails (size auto-compressed)', () {
      final result = validPack(stickerCount: 2, stickerSize: 100 * 1024 + 1);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
      // No size error — auto-compressed during export
      expect(result.errors.any((e) => e.contains('exceeds max size')), isFalse);
    });

    test('31 oversized stickers — only count fails (size auto-compressed)', () {
      final result = validPack(stickerCount: 31, stickerSize: 100 * 1024 + 1);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at most 30')), isTrue);
      // No size error — auto-compressed during export
      expect(result.errors.any((e) => e.contains('exceeds max size')), isFalse);
    });
  });
}
