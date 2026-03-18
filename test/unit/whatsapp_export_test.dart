import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_officer/features/export/data/whatsapp_export_service.dart';

void main() {
  late WhatsAppExportService service;

  setUp(() {
    service = WhatsAppExportService();
  });

  group('WhatsApp Pack Validation', () {
    test('rejects empty pack name', () {
      final result = service.validatePack(
        name: '',
        stickers: List.generate(
          3,
          (_) => StickerData(data: Uint8List(1000)),
        ),
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, false);
      expect(result.errors, contains('Pack name is required'));
    });

    test('rejects fewer than 3 stickers', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: [StickerData(data: Uint8List(1000))],
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('at least 3')), true);
    });

    test('rejects more than 30 stickers', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: List.generate(
          31,
          (_) => StickerData(data: Uint8List(1000)),
        ),
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('at most 30')), true);
    });

    test('rejects missing tray icon', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: List.generate(
          5,
          (_) => StickerData(data: Uint8List(1000)),
        ),
        trayIcon: null,
      );

      expect(result.isValid, false);
      expect(result.errors, contains('Tray icon is required'));
    });

    test('rejects sticker exceeding 100KB', () {
      final result = service.validatePack(
        name: 'Test Pack',
        stickers: [
          StickerData(data: Uint8List(200 * 1024)), // 200KB
          StickerData(data: Uint8List(1000)),
          StickerData(data: Uint8List(1000)),
        ],
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('exceeds max size')), true);
    });

    test('accepts valid pack', () {
      final result = service.validatePack(
        name: 'My Sticker Pack',
        stickers: List.generate(
          5,
          (_) => StickerData(data: Uint8List(50 * 1024)), // 50KB each
        ),
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, true);
      expect(result.errors, isEmpty);
    });

    test('allows animated stickers up to 500KB', () {
      final result = service.validatePack(
        name: 'Animated Pack',
        stickers: List.generate(
          3,
          (_) => StickerData(
            data: Uint8List(400 * 1024), // 400KB
            isAnimated: true,
          ),
        ),
        trayIcon: Uint8List(100),
      );

      expect(result.isValid, true);
    });
  });
}
