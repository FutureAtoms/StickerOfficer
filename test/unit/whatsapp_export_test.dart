import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_officer/features/export/data/whatsapp_export_service.dart';

void main() {
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

    test('rejects sticker at 100KB + 1 byte', () {
      final result = validPack(stickerCount: 3, stickerSize: 100 * 1024 + 1);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('exceeds max size')), isTrue);
    });

    test('rejects sticker at 200KB', () {
      final result = validPack(stickerCount: 3, stickerSize: 200 * 1024);

      expect(result.isValid, isFalse);
    });

    test('error message includes sticker index (1-based)', () {
      final stickers = [
        StickerData(data: Uint8List(1000)),
        StickerData(data: Uint8List(1000)),
        StickerData(data: Uint8List(200 * 1024)), // third sticker is oversized
      ];

      final result = service.validatePack(
        name: 'Test Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Sticker 3')), isTrue);
    });

    test('error message includes size in KB', () {
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

      expect(result.errors.any((e) => e.contains('200KB')), isTrue);
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

    test('rejects animated sticker at 500KB + 1 byte', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 500 * 1024 + 1, isAnimated: true),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('exceeds max size')), isTrue);
    });

    test('accepts animated sticker at 400KB (between static and animated limit)', () {
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 400 * 1024, isAnimated: true),
      );

      expect(result.isValid, isTrue);
    });

    test('rejects static sticker at 200KB even though animated would pass', () {
      // 200KB > 100KB static limit, but < 500KB animated limit.
      // Since isAnimated is false, should fail.
      final result = validPack(
        stickers: makeStickers(3, sizeBytes: 200 * 1024, isAnimated: false),
      );

      expect(result.isValid, isFalse);
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

    test('fails when only the static sticker is oversized in a mixed pack', () {
      final stickers = [
        StickerData(data: Uint8List(200 * 1024), isAnimated: false), // TOO BIG
        StickerData(data: Uint8List(400 * 1024), isAnimated: true), // OK
        StickerData(data: Uint8List(50 * 1024), isAnimated: false), // OK
      ];

      final result = service.validatePack(
        name: 'Mixed Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.length, 1);
      expect(result.errors.first, contains('Sticker 1'));
    });

    test('fails when only the animated sticker is oversized in a mixed pack', () {
      final stickers = [
        StickerData(data: Uint8List(80 * 1024), isAnimated: false), // OK
        StickerData(data: Uint8List(600 * 1024), isAnimated: true), // TOO BIG
        StickerData(data: Uint8List(50 * 1024), isAnimated: false), // OK
      ];

      final result = service.validatePack(
        name: 'Mixed Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.length, 1);
      expect(result.errors.first, contains('Sticker 2'));
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

    test('reports oversized errors for multiple stickers', () {
      final stickers = [
        StickerData(data: Uint8List(200 * 1024)), // oversized
        StickerData(data: Uint8List(300 * 1024)), // oversized
        StickerData(data: Uint8List(50 * 1024)), // OK
      ];

      final result = service.validatePack(
        name: 'Test Pack',
        stickers: stickers,
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.length, 2);
      expect(result.errors.any((e) => e.contains('Sticker 1')), isTrue);
      expect(result.errors.any((e) => e.contains('Sticker 2')), isTrue);
    });

    test('collects empty name, missing tray, AND oversized sticker errors together', () {
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
      // Should contain: name error, tray icon error, 3 sticker size errors
      expect(result.errors.length, 5);
      expect(result.errors, contains('Pack name is required'));
      expect(result.errors, contains('Tray icon is required'));
      expect(result.errors.where((e) => e.contains('exceeds max size')).length, 3);
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
    test('returns success for a valid pack', () async {
      final result = await service.exportToWhatsApp(
        packName: 'My Stickers',
        packAuthor: 'Test Author',
        stickers: makeStickers(5, sizeBytes: 10 * 1024),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isTrue);
      expect(result.message, contains('My Stickers'));
      expect(result.message, contains('added to WhatsApp'));
    });

    test('success message includes the pack name in quotes', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Funny Cats',
        packAuthor: 'Author',
        stickers: makeStickers(3),
        trayIcon: Uint8List(100),
      );

      expect(result.message, 'Pack "Funny Cats" added to WhatsApp!');
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

    test('validates before exporting — rejects oversized sticker', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Test Pack',
        packAuthor: 'Author',
        stickers: makeStickers(3, sizeBytes: 200 * 1024),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('exceeds max size'));
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

    test('succeeds with minimum valid pack (3 stickers)', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Min Pack',
        packAuthor: 'Author',
        stickers: makeStickers(3),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isTrue);
    });

    test('succeeds with maximum valid pack (30 stickers)', () async {
      final result = await service.exportToWhatsApp(
        packName: 'Max Pack',
        packAuthor: 'Author',
        stickers: makeStickers(30),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isTrue);
    });

    test('trayIcon is passed to validatePack as non-null (always passes tray check)',
        () async {
      // exportToWhatsApp requires a non-null trayIcon parameter, so the null
      // tray icon validation path is only reachable via validatePack directly.
      final result = await service.exportToWhatsApp(
        packName: 'Pack',
        packAuthor: 'Author',
        stickers: makeStickers(3),
        trayIcon: Uint8List(1),
      );

      expect(result.success, isTrue);
    });

    test('packAuthor is accepted but does not affect validation', () async {
      // Empty author should still succeed — no validation on author.
      final result = await service.exportToWhatsApp(
        packName: 'Pack',
        packAuthor: '',
        stickers: makeStickers(3),
        trayIcon: Uint8List(100),
      );

      expect(result.success, isTrue);
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

    test('2 stickers at 100KB + 1 byte each — both count and size fail', () {
      final result = validPack(stickerCount: 2, stickerSize: 100 * 1024 + 1);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 3')), isTrue);
      expect(result.errors.any((e) => e.contains('exceeds max size')), isTrue);
    });

    test('31 stickers at 100KB + 1 byte each — both count and size fail', () {
      final result = validPack(stickerCount: 31, stickerSize: 100 * 1024 + 1);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at most 30')), isTrue);
      expect(result.errors.any((e) => e.contains('exceeds max size')), isTrue);
    });
  });
}
