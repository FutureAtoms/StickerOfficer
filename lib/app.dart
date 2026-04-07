import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'data/providers.dart';
import 'features/import/data/shared_sticker_import_channel.dart';
import 'features/import/data/shared_sticker_import_service.dart';

class StickerOfficerApp extends ConsumerStatefulWidget {
  const StickerOfficerApp({super.key});

  @override
  ConsumerState<StickerOfficerApp> createState() => _StickerOfficerAppState();
}

class _StickerOfficerAppState extends ConsumerState<StickerOfficerApp> {
  final SharedStickerImportService _importService = SharedStickerImportService();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _isImporting = false;
  List<SharedStickerImportFile>? _queuedFiles;

  @override
  void initState() {
    super.initState();
    SharedStickerImportChannel.setListener(_enqueueImport);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await SharedStickerImportChannel.getPendingFiles();
        await _enqueueImport(pending);
      } catch (_) {
        // Platform channel may not be ready on first launch
      }
    });
  }

  @override
  void dispose() {
    SharedStickerImportChannel.clearListener();
    super.dispose();
  }

  Future<void> _enqueueImport(List<SharedStickerImportFile> files) async {
    if (files.isEmpty) {
      return;
    }

    if (_isImporting) {
      _queuedFiles = files;
      return;
    }

    _isImporting = true;
    var currentFiles = files;

    try {
      while (currentFiles.isNotEmpty) {
        _queuedFiles = null;
        await _importSharedFiles(currentFiles);
        currentFiles = _queuedFiles ?? const [];
      }
    } finally {
      _isImporting = false;
    }
  }

  Future<void> _importSharedFiles(List<SharedStickerImportFile> files) async {
    final messenger = _scaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Importing shared stickers...')),
    );

    try {
      final pack = await _importService.importFiles(files);
      await ref.read(packsProvider.notifier).addPack(pack);

      if (!mounted) {
        return;
      }

      ref.invalidate(packsProvider);
      final router = ref.read(appRouterProvider);
      router.go('/pack/${pack.id}');
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${pack.stickerPaths.length} sticker${pack.stickerPaths.length == 1 ? '' : 's'} into "${pack.name}".',
            ),
          ),
        );
    } on SharedStickerImportException catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Shared import failed: ${error.toString().split('\n').first}',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final stickerTheme = ref.watch(stickerThemeProvider);

    return MaterialApp.router(
      title: 'StickerOfficer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromStickerTheme(stickerTheme),
      darkTheme: AppTheme.dark,
      themeMode: stickerTheme.isDark ? ThemeMode.dark : ThemeMode.light,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      routerConfig: router,
    );
  }
}
