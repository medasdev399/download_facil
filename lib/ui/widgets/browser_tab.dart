import 'package:flutter/material.dart';
import '../../models/download_item.dart';
import '../../models/media_format_option.dart';
import '../../services/log_service.dart';
import '../../services/media_detector_service.dart';
import '../../services/youtube_service.dart';
import '../dialogs/media_format_selector_dialog.dart';

class BrowserTab extends StatefulWidget {
  final String? defaultDirectory;
  final void Function(DownloadItem item) onStartDownload;

  const BrowserTab({
    super.key,
    this.defaultDirectory,
    required this.onStartDownload,
  });

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  final TextEditingController _urlController = TextEditingController(text: 'https://www.youtube.com');
  final List<String> _history = [];
  int _historyIndex = -1;

  bool _isLoading = false;
  String? _errorMessage;
  DetectedMediaInfo? _detectedMedia;
  String _currentLoadedUrl = '';

  final List<Map<String, String>> _quickLinks = [
    {'name': 'YouTube', 'url': 'https://www.youtube.com', 'icon': 'youtube'},
    {'name': 'SoundCloud', 'url': 'https://soundcloud.com', 'icon': 'music'},
    {'name': 'Vimeo', 'url': 'https://vimeo.com', 'icon': 'vimeo'},
    {'name': 'Dailymotion', 'url': 'https://www.dailymotion.com', 'icon': 'video'},
    {'name': 'TikTok', 'url': 'https://www.tiktok.com', 'icon': 'video'},
    {'name': 'Archive.org', 'url': 'https://archive.org', 'icon': 'archive'},
  ];

  @override
  void initState() {
    super.initState();
    _navigateTo('https://www.youtube.com');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _navigateTo(String url) {
    var clean = url.trim();
    if (clean.isEmpty) return;

    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      if (clean.contains('.') && !clean.contains(' ')) {
        clean = 'https://$clean';
      } else {
        // Se for termo de busca, pesquisa no YouTube
        clean = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(clean)}';
      }
    }

    _urlController.text = clean;
    if (_history.isEmpty || _history.last != clean) {
      if (_historyIndex < _history.length - 1 && _historyIndex >= 0) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(clean);
      _historyIndex = _history.length - 1;
    }

    _inspectUrl(clean);
  }

  void _goBack() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        final url = _history[_historyIndex];
        _urlController.text = url;
      });
      _inspectUrl(_history[_historyIndex]);
    }
  }

  void _goForward() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        final url = _history[_historyIndex];
        _urlController.text = url;
      });
      _inspectUrl(_history[_historyIndex]);
    }
  }

  Future<void> _inspectUrl(String url) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentLoadedUrl = url;
    });

    LogService.info('Navegador acessando: $url', tag: 'Navegador');

    try {
      final media = await MediaDetectorService.detectFromUrl(url);
      if (mounted) {
        setState(() {
          _detectedMedia = media;
          _isLoading = false;
        });

        if (media != null && media.totalOptionsCount > 0) {
          LogService.info(
            'Mídia detectada no navegador: "${media.title}" (${media.totalOptionsCount} formatos)',
            tag: 'Navegador',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openDownloadModal() async {
    if (_detectedMedia == null) return;

    final result = await MediaFormatSelectorDialog.show(
      context,
      mediaInfo: _detectedMedia!,
      defaultDirectory: widget.defaultDirectory,
    );

    if (result != null && mounted) {
      final isYouTube = _detectedMedia!.isYouTube || YouTubeService.isYouTubeUrl(_detectedMedia!.url);
      final streamIdIsUrl = result.option.streamId != null &&
          (result.option.streamId!.startsWith('http://') || result.option.streamId!.startsWith('https://'));
      final streamUrl = (!isYouTube && streamIdIsUrl)
          ? result.option.streamId!
          : _detectedMedia!.url;

      final newItem = DownloadItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        url: streamUrl,
        fileName: result.fileName,
        savePath: result.savePath,
        mediaType: result.mediaType,
        thumbnailUrl: _detectedMedia!.thumbnailUrl,
        author: _detectedMedia!.author,
        duration: _detectedMedia!.duration,
        quality: result.option.qualityTag,
        targetFormat: result.option.extension,
        audioBitrate: result.option.qualityTag,
        selectedStreamId: result.option.streamId,
        httpHeaders: result.option.httpHeaders,
      );

      widget.onStartDownload(newItem);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download de "${result.fileName}" iniciado!'),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasMedia = _detectedMedia != null && _detectedMedia!.totalOptionsCount > 0;

    return Column(
      children: [
        // Barra de navegação e endereço
        _buildAddressBar(colorScheme),

        if (_isLoading) const LinearProgressIndicator(minHeight: 3),

        // Atalhos de sites populares
        _buildQuickLinksRow(colorScheme),

        const Divider(height: 1),

        // Conteúdo da página do navegador e sniffer de mídia
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Banner de mídia detectada rodando no navegador
                    if (hasMedia) ...[
                      _buildDetectedMediaBanner(colorScheme),
                      const SizedBox(height: 16),
                    ],

                    // Painel de status e monitoramento de streaming da página
                    _buildPageMonitorCard(theme, colorScheme),
                    const SizedBox(height: 16),

                    // Lista de mídias e formatos farejados
                    if (hasMedia) _buildSniffedStreamsList(colorScheme),
                  ],
                ),
              ),

              // Botão Flutuante de Download Rápido quando mídia estiver disponível
              if (hasMedia)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.extended(
                    onPressed: _openDownloadModal,
                    elevation: 6,
                    backgroundColor: Colors.redAccent,
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    label: Text(
                      'Baixar Mídia (${_detectedMedia!.totalOptionsCount})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Voltar',
            onPressed: _historyIndex > 0 ? _goBack : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Avançar',
            onPressed: _historyIndex < _history.length - 1 ? _goForward : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: () => _inspectUrl(_urlController.text),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'Digite uma URL ou termo de busca...',
                prefixIcon: const Icon(Icons.language, size: 20),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _urlController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                filled: true,
                fillColor: colorScheme.surface,
              ),
              onSubmitted: _navigateTo,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () => _navigateTo(_urlController.text),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Ir'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinksRow(ColorScheme colorScheme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _quickLinks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final link = _quickLinks[index];
          final isSelected = _currentLoadedUrl.startsWith(link['url']!);

          return Center(
            child: ActionChip(
              avatar: Icon(
                link['name'] == 'YouTube'
                    ? Icons.play_circle_filled
                    : link['name'] == 'SoundCloud'
                        ? Icons.graphic_eq
                        : Icons.public,
                size: 16,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              label: Text(link['name']!),
              onPressed: () => _navigateTo(link['url']!),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetectedMediaBanner(ColorScheme colorScheme) {
    final media = _detectedMedia!;

    return Card(
      elevation: 4,
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (media.thumbnailUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  media.thumbnailUrl!,
                  width: 90,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 90,
                    height: 60,
                    color: Colors.black12,
                    child: const Icon(Icons.play_arrow),
                  ),
                ),
              )
            else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.movie_creation, color: Colors.white, size: 30),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'MÍDIA DETECTADA',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        media.formattedDuration,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (media.author != null)
                    Text(
                      media.author!,
                      style: TextStyle(color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: _openDownloadModal,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Baixar com Tipos e Formatos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          // Abre com opção de áudio direta
                          _openDownloadModal();
                        },
                        icon: const Icon(Icons.music_note, size: 18),
                        label: const Text('Extrair MP3'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageMonitorCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isLoading ? Icons.sync : Icons.radar,
                  color: _isLoading ? Colors.orange : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isLoading ? 'Farejando mídias na página...' : 'Sniffer de Mídia Ativo',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 8),
                      SizedBox(width: 4),
                      Text('Online', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Página atual: $_currentLoadedUrl',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            const Text(
              'O navegador detecta automaticamente qualquer vídeo ou áudio reproduzido na página atual '
              '(tags <video>, <audio>, YouTube, MP4, MP3, WebM, HLS). Ao identificar o conteúdo, você pode '
              'escolher a resolução e formato desejados.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSniffedStreamsList(ColorScheme colorScheme) {
    final media = _detectedMedia!;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Formatos e Qualidades Disponíveis para Download:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),

            if (media.videoFormats.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.videocam_rounded, size: 18, color: Colors.blueAccent),
                  SizedBox(width: 6),
                  Text('Opções de Vídeo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: media.videoFormats.map((opt) {
                  return ActionChip(
                    avatar: const Icon(Icons.download, size: 14),
                    label: Text('${opt.label} ${opt.formattedSize.isNotEmpty ? "(${opt.formattedSize})" : ""}'),
                    onPressed: _openDownloadModal,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            if (media.audioFormats.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.music_note_rounded, size: 18, color: Colors.purpleAccent),
                  SizedBox(width: 6),
                  Text('Opções de Áudio / Música:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: media.audioFormats.map((opt) {
                  return ActionChip(
                    avatar: const Icon(Icons.music_note, size: 14),
                    label: Text('${opt.label} ${opt.formattedSize.isNotEmpty ? "(${opt.formattedSize})" : ""}'),
                    onPressed: _openDownloadModal,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

