import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/conversion_item.dart';
import '../../services/storage_resolver.dart';
import 'log_viewer_dialog.dart';

class ConversionCard extends StatelessWidget {
  final ConversionItem conversion;

  const ConversionCard({
    super.key,
    required this.conversion,
  });

  @override
  Widget build(BuildContext context) {
    final isConverting = conversion.status == ConversionStatus.converting;
    final isCompleted = conversion.status == ConversionStatus.completed;
    final isFailed = conversion.status == ConversionStatus.failed;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isCompleted
                      ? Colors.green.withValues(alpha: 0.2)
                      : (isFailed
                          ? Colors.red.withValues(alpha: 0.2)
                          : Colors.blue.withValues(alpha: 0.2)),
                  child: Icon(
                    isCompleted
                        ? Icons.check
                        : (isFailed ? Icons.error_outline : Icons.sync),
                    color: isCompleted
                        ? Colors.green
                        : (isFailed ? Colors.red : Colors.blue),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${conversion.inputFileName} ➔ ${conversion.outputFileName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Formato: ${conversion.targetFormat.toUpperCase()} • Bitrate: ${conversion.audioBitrate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (isCompleted && !kIsWeb) ...[
                  IconButton.filledTonal(
                    tooltip: 'Abrir Arquivo Convertido',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => StorageResolver.openFile(conversion.outputPath),
                  ),
                  IconButton(
                    tooltip: 'Abrir Pasta',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => StorageResolver.openDirectory(p.dirname(conversion.outputPath)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: isConverting
                    ? (conversion.progress > 0 ? conversion.progress : null)
                    : (isCompleted ? 1.0 : 0.0),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    isConverting
                        ? 'Processando... ${(conversion.progress * 100).toStringAsFixed(0)}%'
                        : (isCompleted ? 'Conversão Concluída!' : (conversion.errorMessage ?? 'Falha na conversão')),
                    style: TextStyle(
                      fontSize: 12,
                      color: isCompleted ? Colors.green : (isFailed ? Colors.red : null),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isFailed)
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
          ],
        ),
      ),
    );
  }
}

