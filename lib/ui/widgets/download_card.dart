import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/download_item.dart';
import '../../services/storage_resolver.dart';
import 'log_viewer_dialog.dart';

class DownloadCard extends StatelessWidget {
  final DownloadItem item;
  final bool isDesktop;
  final bool ffmpegAvailable;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final VoidCallback onExtractAudio;
  final VoidCallback onOpenConvertDialog;

  const DownloadCard({
    super.key,
    required this.item,
    required this.isDesktop,
    required this.ffmpegAvailable,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    required this.onExtractAudio,
    required this.onOpenConvertDialog,
  });

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildStatusIcon(DownloadStatus status, DownloadMediaType mediaType) {
    if (status == DownloadStatus.downloading) {
      return const CircleAvatar(
        radius: 18,
        child: Icon(Icons.downloading_rounded, size: 20),
      );
    } else if (status == DownloadStatus.converting) {
      return const CircleAvatar(
        radius: 18,
        child: Icon(Icons.sync, size: 20),
      );
    } else if (status == DownloadStatus.paused) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.orange.withValues(alpha: 0.2),
        child: const Icon(Icons.pause_circle_outline, color: Colors.orange, size: 20),
      );
    } else if (status == DownloadStatus.completed) {
      final icon = mediaType == DownloadMediaType.music
          ? Icons.music_note
          : (mediaType == DownloadMediaType.video ? Icons.movie : Icons.check_circle_outline);
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.green.withValues(alpha: 0.2),
        child: Icon(icon, color: Colors.green, size: 20),
      );
    } else if (status == DownloadStatus.failed) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.red.withValues(alpha: 0.2),
        child: const Icon(Icons.error_outline, color: Colors.red, size: 20),
      );
    }
    return const CircleAvatar(
      radius: 18,
      child: Icon(Icons.schedule, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDownloading = item.status == DownloadStatus.downloading;
    final isConverting = item.status == DownloadStatus.converting;
    final isPaused = item.status == DownloadStatus.paused;
    final isCompleted = item.status == DownloadStatus.completed;
    final isFailed = item.status == DownloadStatus.failed;

    final percentage = (item.progress * 100).toStringAsFixed(1);
    final isVideoFile = item.fileName.endsWith('.mp4') ||
        item.fileName.endsWith('.mkv') ||
        item.fileName.endsWith('.webm') ||
        item.fileName.endsWith('.avi');

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (item.thumbnailUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      item.thumbnailUrl!,
                      width: 52,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _buildStatusIcon(item.status, item.mediaType),
                    ),
                  )
                else
                  _buildStatusIcon(item.status, item.mediaType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.fileName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.mediaType == DownloadMediaType.music)
                            const Chip(
                              label: Text('Música', style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            )
                          else if (item.mediaType == DownloadMediaType.video)
                            const Chip(
                              label: Text('Vídeo', style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.author != null ? '${item.author} • ${item.url}' : item.url,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Botões de Ação
                if (isDownloading)
                  IconButton.filledTonal(
                    tooltip: 'Pausar',
                    icon: const Icon(Icons.pause_rounded),
                    onPressed: onPause,
                  )
                else if (isPaused || isFailed)
                  IconButton.filled(
                    tooltip: 'Retomar',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: onResume,
                  ),
                if (isCompleted && !kIsWeb) ...[
                  IconButton.filledTonal(
                    tooltip: 'Abrir Arquivo',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => StorageResolver.openFile(item.savePath),
                  ),
                  IconButton(
                    tooltip: 'Abrir Pasta',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => StorageResolver.openDirectory(p.dirname(item.savePath)),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Remover da lista',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: isConverting
                    ? null
                    : (item.totalBytes > 0 ? item.progress : (isDownloading ? null : 0.0)),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isConverting
                      ? (item.statusMessage ?? 'Processando áudio com FFmpeg...')
                      : (item.totalBytes > 0
                          ? '${formatBytes(item.downloadedBytes)} de ${formatBytes(item.totalBytes)} ($percentage%)'
                          : formatBytes(item.downloadedBytes)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (isDownloading)
                  Text(
                    item.formattedSpeed,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  )
                else if (isConverting)
                  const Text('Convertendo...', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold))
                else if (isPaused)
                  const Text('Pausado', style: TextStyle(fontSize: 12, color: Colors.orange))
                else if (isCompleted)
                  const Text('Concluído', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold))
                else if (isFailed)
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            item.errorMessage ?? 'Falha no download',
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => LogViewerDialog.show(context),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bug_report, size: 14, color: Colors.redAccent),
                                SizedBox(width: 2),
                                Text(
                                  'Ver log',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.redAccent,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            // Ações extras para itens de vídeo concluídos: Extrair Áudio ou Converter
            if (isCompleted && !kIsWeb && ffmpegAvailable) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (isVideoFile)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.music_note, size: 16),
                      label: const Text('Extrair MP3', style: TextStyle(fontSize: 12)),
                      onPressed: onExtractAudio,
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.transform_rounded, size: 16),
                    label: const Text('Converter Formato', style: TextStyle(fontSize: 12)),
                    onPressed: onOpenConvertDialog,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

