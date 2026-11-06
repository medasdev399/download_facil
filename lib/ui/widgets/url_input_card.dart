import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/media_format_option.dart';
import '../../services/youtube_service.dart';

class UrlInputCard extends StatelessWidget {
  final TextEditingController controller;
  final String selectedMode;
  final bool isDesktop;
  final bool fetchingPreview;
  final YouTubeMediaInfo? youtubePreview;
  final DetectedMediaInfo? detectedMedia;
  final String? previewError;
  final String? customDirectory;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onUrlChanged;
  final VoidCallback onAddDownload;
  final VoidCallback onOpenFormatSelector;
  final VoidCallback onPaste;
  final VoidCallback onPickDirectory;

  const UrlInputCard({
    super.key,
    required this.controller,
    required this.selectedMode,
    required this.isDesktop,
    required this.fetchingPreview,
    required this.youtubePreview,
    this.detectedMedia,
    required this.previewError,
    required this.customDirectory,
    required this.onModeChanged,
    required this.onUrlChanged,
    required this.onAddDownload,
    required this.onOpenFormatSelector,
    required this.onPaste,
    required this.onPickDirectory,
  });

  Widget _buildMediaPreviewWidget(BuildContext context) {
    final title = detectedMedia?.title ?? youtubePreview?.title ?? 'Mídia Detectada';
    final author = detectedMedia?.author ?? youtubePreview?.author;
    final durText = detectedMedia?.formattedDuration ?? '';
    final thumb = detectedMedia?.thumbnailUrl ?? youtubePreview?.thumbnailUrl;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: thumb != null && thumb.isNotEmpty
                    ? Image.network(
                        thumb,
                        width: 86,
                        height: 54,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.play_circle_fill, size: 48),
                      )
                    : Container(
                        width: 86,
                        height: 54,
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.play_circle_fill, size: 36),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author != null ? '$author • $durText' : durText,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    if (detectedMedia != null)
                      Text(
                        '${detectedMedia!.videoFormats.length} vídeo(s) e ${detectedMedia!.audioFormats.length} áudio(s) disponíveis',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenFormatSelector,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Escolher Tipos e Formatos (Resoluções / MP3)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrlTextField() {
    return TextField(
      controller: controller,
      onChanged: onUrlChanged,
      onSubmitted: (_) => onAddDownload(),
      decoration: InputDecoration(
        hintText: 'Cole o link direto, vídeo ou música (YouTube, MP4, MP3...)',
        prefixIcon: const Icon(Icons.link),
        suffixIcon: IconButton(
          tooltip: 'Colar da área de transferência',
          icon: const Icon(Icons.content_paste_rounded),
          onPressed: onPaste,
        ),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Seletor de Modo: Automático / Vídeo / Música
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Tipo:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 2),
                ChoiceChip(
                  label: const Text('⚡ Automático'),
                  selected: selectedMode == 'auto',
                  onSelected: (val) => onModeChanged('auto'),
                ),
                ChoiceChip(
                  label: const Text('🎬 Vídeo (MP4)'),
                  selected: selectedMode == 'video',
                  onSelected: (val) => onModeChanged('video'),
                ),
                ChoiceChip(
                  label: const Text('🎵 Música (MP3)'),
                  selected: selectedMode == 'music',
                  onSelected: (val) => onModeChanged('music'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isDesktop)
              Row(
                children: [
                  Expanded(child: _buildUrlTextField()),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: onAddDownload,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(selectedMode == 'music' ? 'Baixar Música' : 'Baixar Agora'),
                    ),
                  ),
                ],
              )
            else ...[
              _buildUrlTextField(),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: onAddDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(selectedMode == 'music' ? 'Baixar Música' : 'Baixar Agora'),
                ),
              ),
            ],
            // Pré-visualização de mídia se detectada
            if (fetchingPreview) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (detectedMedia != null || youtubePreview != null) ...[
              const SizedBox(height: 12),
              _buildMediaPreviewWidget(context),
            ] else if (previewError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        previewError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!kIsWeb && customDirectory != null) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: onPickDirectory,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Salvar em: $customDirectory',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text(
                        'Trocar',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
