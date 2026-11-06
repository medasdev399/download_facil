import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/conversion_item.dart';
import '../models/download_item.dart';
import '../services/engine/download_engine.dart';
import '../services/ffmpeg_service.dart';
import '../services/log_service.dart';
import '../services/storage_resolver.dart';
import '../services/youtube_service.dart';
import 'dialogs/convert_media_dialog.dart';
import 'widgets/conversion_card.dart';
import 'widgets/download_card.dart';
import 'widgets/ffmpeg_status_card.dart';
import 'widgets/local_conversion_card.dart';
import 'widgets/log_viewer_dialog.dart';
import 'widgets/url_input_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _urlController = TextEditingController();
  final DownloadEngine _engine = DownloadEngine();

  final List<DownloadItem> _downloads = [];
  final List<ConversionItem> _conversions = [];

  String? _customDirectory;
  String _selectedFilter = 'all'; // all, active, completed
  String _selectedMode = 'auto'; // auto, video, music

  bool _ffmpegAvailable = false;
  bool _fetchingPreview = false;
  String? _previewError;
  Timer? _debounceTimer;
  int _previewRequestId = 0;
  YouTubeMediaInfo? _youtubePreview;

  // Variáveis da aba Conversor
  String? _selectedConvertSourcePath;
  String _targetFormat = 'mp3';
  String _targetBitrate = '192k';
  bool _isConvertingLocal = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initDefaultDirectory();
    _checkFFmpeg();
  }

  Future<void> _initDefaultDirectory() async {
    if (!kIsWeb) {
      final defaultFile = await StorageResolver.getDefaultSavePath('teste.tmp');
      if (mounted) {
        setState(() {
          _customDirectory = p.dirname(defaultFile);
        });
      }
    }
  }

  Future<void> _checkFFmpeg() async {
    final available = await FFmpegService.isAvailable();
    if (mounted) {
      setState(() {
        _ffmpegAvailable = available;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _urlController.dispose();
    for (final item in _downloads) {
      _engine.pause(item);
    }
    super.dispose();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final validSegment = uri.pathSegments.reversed.firstWhere(
        (segment) => segment.trim().isNotEmpty,
        orElse: () => '',
      );
      if (validSegment.isNotEmpty) {
        final decoded = Uri.decodeComponent(validSegment);
        final sanitized = _sanitizeFileName(decoded);
        if (sanitized.isNotEmpty) return sanitized;
      }
    } catch (_) {}
    return 'arquivo_${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  void _onUrlChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _executeUrlChanged(text);
    });
  }

  Future<void> _executeUrlChanged(String text) async {
    final clean = text.trim();
    if (!YouTubeService.isYouTubeUrl(clean)) {
      if (_youtubePreview != null || _fetchingPreview || _previewError != null) {
        setState(() {
          _youtubePreview = null;
          _fetchingPreview = false;
          _previewError = null;
        });
      }
      return;
    }

    final currentId = ++_previewRequestId;
    setState(() {
      _fetchingPreview = true;
      _previewError = null;
    });

    try {
      final info = await YouTubeService.fetchInfo(clean);
      if (!mounted || currentId != _previewRequestId) return;
      setState(() {
        _youtubePreview = info;
        _fetchingPreview = false;
        _previewError = null;
      });
    } catch (e) {
      if (!mounted || currentId != _previewRequestId) return;
      setState(() {
        _youtubePreview = null;
        _fetchingPreview = false;
        _previewError = YouTubeService.formatErrorMessage(e);
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      final text = data.text!.trim();
      setState(() {
        _urlController.text = text;
      });
      _onUrlChanged(text);
    }
  }

  Future<void> _pickDirectory() async {
    final picked = await StorageResolver.pickCustomDirectory();
    if (picked != null && mounted) {
      setState(() {
        _customDirectory = picked;
      });
    }
  }

  Future<void> _addDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insira uma URL válida começando com http:// ou https://')),
      );
      return;
    }

    final isYouTube = YouTubeService.isYouTubeUrl(url);
    DownloadMediaType mediaType = DownloadMediaType.general;

    if (_selectedMode == 'music') {
      mediaType = DownloadMediaType.music;
    } else if (_selectedMode == 'video') {
      mediaType = DownloadMediaType.video;
    } else if (isYouTube) {
      mediaType = DownloadMediaType.video;
    }

    String fileName;
    if (_youtubePreview != null) {
      final safeTitle = _sanitizeFileName(_youtubePreview!.title);
      final ext = mediaType == DownloadMediaType.music ? 'mp3' : 'mp4';
      fileName = '$safeTitle.$ext';
    } else {
      fileName = _extractFileName(url);
      if (mediaType == DownloadMediaType.music && !fileName.endsWith('.mp3')) {
        fileName = '${p.withoutExtension(fileName)}.mp3';
      } else if (mediaType == DownloadMediaType.video && !fileName.endsWith('.mp4')) {
        fileName = '${p.withoutExtension(fileName)}.mp4';
      }
    }

    String savePath;
    if (kIsWeb) {
      savePath = fileName;
    } else if (_customDirectory != null) {
      savePath = p.join(_customDirectory!, fileName);
    } else {
      savePath = await StorageResolver.getDefaultSavePath(fileName);
    }

    if (!mounted) return;

    final newItem = DownloadItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      fileName: fileName,
      savePath: savePath,
      mediaType: mediaType,
      thumbnailUrl: _youtubePreview?.thumbnailUrl,
      author: _youtubePreview?.author,
      duration: _youtubePreview?.duration,
    );

    LogService.info(
      'Adicionando download: "$fileName"',
      tag: 'UI',
      details: 'URL: $url\nDestino: $savePath\nTipo: ${mediaType.name}',
    );

    setState(() {
      _downloads.insert(0, newItem);
      _urlController.clear();
      _youtubePreview = null;
      _previewError = null;
    });

    _startOrResumeItem(newItem);
  }

  void _startOrResumeItem(DownloadItem item) {
    _engine.startOrResume(
      item,
      onUpdate: () {
        if (mounted) {
          setState(() {});
          if (item.status == DownloadStatus.failed && item.errorMessage != null) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Falha ao baixar "${item.fileName}": ${item.errorMessage}'),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Ver Logs',
                  textColor: Colors.white,
                  onPressed: () => LogViewerDialog.show(context),
                ),
              ),
            );
          }
        }
      },
    );
  }

  void _pauseItem(DownloadItem item) {
    _engine.pause(item);
  }

  void _removeItem(DownloadItem item) {
    _engine.pause(item);
    setState(() {
      _downloads.removeWhere((element) => element.id == item.id);
    });
  }

  /// Extração rápida de áudio MP3 de um vídeo baixado
  Future<void> _extractAudioFromVideo(DownloadItem item) async {
    if (!_ffmpegAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FFmpeg não encontrado no sistema operacional.')),
      );
      return;
    }

    final targetPath = p.join(
      p.dirname(item.savePath),
      '${p.withoutExtension(item.fileName)}.mp3',
    );

    final conversion = ConversionItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      inputPath: item.savePath,
      outputPath: targetPath,
      inputFileName: item.fileName,
      outputFileName: p.basename(targetPath),
      targetFormat: 'mp3',
      audioBitrate: '320k',
      status: ConversionStatus.converting,
    );

    setState(() {
      _conversions.insert(0, conversion);
      _tabController.animateTo(1); // Alterna para a aba do conversor
    });

    final success = await FFmpegService.convertMedia(
      inputPath: conversion.inputPath,
      outputPath: conversion.outputPath,
      targetFormat: 'mp3',
      audioBitrate: '320k',
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            conversion.progress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        conversion.status = success ? ConversionStatus.completed : ConversionStatus.failed;
        conversion.progress = success ? 1.0 : 0.0;
        if (!success) {
          conversion.errorMessage = 'Erro ao processar conversão com FFmpeg';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Falha na extração de áudio.'),
              backgroundColor: Colors.red.shade800,
              action: SnackBarAction(
                label: 'Ver Logs',
                textColor: Colors.white,
                onPressed: () => LogViewerDialog.show(context),
              ),
            ),
          );
        }
      });
    }
  }

  /// Abre diálogo de conversão personalizada para um item baixado
  Future<void> _openConvertDialog(DownloadItem item) async {
    final result = await ConvertMediaDialog.show(context, item);
    if (result != null && mounted) {
      _startCustomConversion(
        inputPath: item.savePath,
        targetFormat: result.targetFormat,
        bitrate: result.audioBitrate,
      );
    }
  }

  Future<void> _startCustomConversion({
    required String inputPath,
    required String targetFormat,
    String bitrate = '192k',
  }) async {
    final fileName = p.basename(inputPath);
    final outputName = '${p.withoutExtension(fileName)}.$targetFormat';
    final outputPath = p.join(
      _customDirectory ?? p.dirname(inputPath),
      outputName,
    );

    final conversion = ConversionItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      inputPath: inputPath,
      outputPath: outputPath,
      inputFileName: fileName,
      outputFileName: outputName,
      targetFormat: targetFormat,
      audioBitrate: bitrate,
      status: ConversionStatus.converting,
    );

    setState(() {
      _conversions.insert(0, conversion);
      _tabController.animateTo(1);
    });

    final success = await FFmpegService.convertMedia(
      inputPath: inputPath,
      outputPath: outputPath,
      targetFormat: targetFormat,
      audioBitrate: bitrate,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            conversion.progress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        conversion.status = success ? ConversionStatus.completed : ConversionStatus.failed;
        conversion.progress = success ? 1.0 : 0.0;
        if (!success) {
          conversion.errorMessage = 'Falha durante o processamento do FFmpeg';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Falha na conversão de mídia.'),
              backgroundColor: Colors.red.shade800,
              action: SnackBarAction(
                label: 'Ver Logs',
                textColor: Colors.white,
                onPressed: () => LogViewerDialog.show(context),
              ),
            ),
          );
        }
      });
    }
  }

  Future<void> _pickLocalFileForConversion() async {
    final path = await StorageResolver.pickMediaFile();
    if (path != null && mounted) {
      setState(() {
        _selectedConvertSourcePath = path;
      });
    }
  }

  Future<void> _runLocalConversion() async {
    if (_selectedConvertSourcePath == null) return;
    setState(() => _isConvertingLocal = true);

    await _startCustomConversion(
      inputPath: _selectedConvertSourcePath!,
      targetFormat: _targetFormat,
      bitrate: _targetBitrate,
    );

    if (mounted) {
      setState(() {
        _isConvertingLocal = false;
        _selectedConvertSourcePath = null;
      });
    }
  }

  List<DownloadItem> get _filteredDownloads {
    if (_selectedFilter == 'active') {
      return _downloads.where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.converting ||
          d.status == DownloadStatus.paused ||
          d.status == DownloadStatus.pending).toList();
    } else if (_selectedFilter == 'completed') {
      return _downloads.where((d) => d.status == DownloadStatus.completed).toList();
    }
    return _downloads;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded),
            SizedBox(width: 8),
            Text('Download Fácil', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.download_rounded),
              text: 'Downloads (${_downloads.length})',
            ),
            Tab(
              icon: const Icon(Icons.transform_rounded),
              text: 'Conversor (${_conversions.length})',
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: LogService.errorCountNotifier,
            builder: (context, errorCount, _) {
              return IconButton(
                tooltip: 'Console de Logs & Diagnóstico',
                icon: Badge(
                  isLabelVisible: errorCount > 0,
                  label: Text('$errorCount'),
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.terminal_rounded),
                ),
                onPressed: () => LogViewerDialog.show(context),
              );
            },
          ),
          if (!kIsWeb && _customDirectory != null)
            IconButton(
              tooltip: 'Alterar pasta de destino padrão',
              icon: const Icon(Icons.folder_open),
              onPressed: _pickDirectory,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDownloadsTab(),
          _buildConverterTab(),
        ],
      ),
    );
  }

  // ================= ABA DE DOWNLOADS =================

  Widget _buildDownloadsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 700;
        final isShortScreen = constraints.maxHeight < 550;

        final inputCard = UrlInputCard(
          controller: _urlController,
          selectedMode: _selectedMode,
          isDesktop: isDesktop,
          fetchingPreview: _fetchingPreview,
          youtubePreview: _youtubePreview,
          previewError: _previewError,
          customDirectory: _customDirectory,
          onModeChanged: (mode) => setState(() => _selectedMode = mode),
          onUrlChanged: _onUrlChanged,
          onAddDownload: _addDownload,
          onPaste: _pasteFromClipboard,
          onPickDirectory: _pickDirectory,
        );

        if (isShortScreen) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    inputCard,
                    const SizedBox(height: 16),
                    _buildFilterRow(),
                    const SizedBox(height: 12),
                    if (_filteredDownloads.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredDownloads.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _filteredDownloads[index];
                          return DownloadCard(
                            item: item,
                            isDesktop: isDesktop,
                            ffmpegAvailable: _ffmpegAvailable,
                            onPause: () => _pauseItem(item),
                            onResume: () => _startOrResumeItem(item),
                            onRemove: () => _removeItem(item),
                            onExtractAudio: () => _extractAudioFromVideo(item),
                            onOpenConvertDialog: () => _openConvertDialog(item),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  inputCard,
                  const SizedBox(height: 16),
                  _buildFilterRow(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _filteredDownloads.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: _filteredDownloads.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _filteredDownloads[index];
                              return DownloadCard(
                                item: item,
                                isDesktop: isDesktop,
                                ffmpegAvailable: _ffmpegAvailable,
                                onPause: () => _pauseItem(item),
                                onResume: () => _startOrResumeItem(item),
                                onRemove: () => _removeItem(item),
                                onExtractAudio: () => _extractAudioFromVideo(item),
                                onOpenConvertDialog: () => _openConvertDialog(item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('Todos'), icon: Icon(Icons.list)),
            ButtonSegment(value: 'active', label: Text('Ativos'), icon: Icon(Icons.sync)),
            ButtonSegment(value: 'completed', label: Text('Concluídos'), icon: Icon(Icons.check_circle_outline)),
          ],
          selected: {_selectedFilter},
          onSelectionChanged: (selection) {
            setState(() {
              _selectedFilter = selection.first;
            });
          },
        ),
        Text(
          '${_filteredDownloads.length} item(ns)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhum download por aqui ainda',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Cole links do YouTube ou URLs diretas de vídeos, músicas e arquivos.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= ABA DE CONVERSÃO =================

  Widget _buildConverterTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 700;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FFmpegStatusCard(isAvailable: _ffmpegAvailable),
                  const SizedBox(height: 16),
                  LocalConversionCard(
                    isDesktop: isDesktop,
                    selectedFilePath: _selectedConvertSourcePath,
                    targetFormat: _targetFormat,
                    targetBitrate: _targetBitrate,
                    isConverting: _isConvertingLocal,
                    ffmpegAvailable: _ffmpegAvailable,
                    onPickFile: _pickLocalFileForConversion,
                    onFormatChanged: (fmt) => setState(() => _targetFormat = fmt),
                    onBitrateChanged: (bit) => setState(() => _targetBitrate = bit),
                    onStartConversion: _runLocalConversion,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Histórico de Conversões (${_conversions.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (_conversions.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _conversions.clear()),
                          child: const Text('Limpar Histórico'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_conversions.isEmpty)
                    _buildConverterEmptyState()
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _conversions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final conv = _conversions[index];
                        return ConversionCard(conversion: conv);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConverterEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_horiz_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma conversão recente',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Converta qualquer vídeo do PC para MP3, WAV, AAC, ou alterne entre formatos de vídeo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
