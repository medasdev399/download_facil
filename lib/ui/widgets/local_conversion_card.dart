import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/ffmpeg_service.dart';

class LocalConversionCard extends StatelessWidget {
  final bool isDesktop;
  final String? selectedFilePath;
  final String targetFormat;
  final String targetBitrate;
  final bool isConverting;
  final bool ffmpegAvailable;
  final VoidCallback onPickFile;
  final ValueChanged<String> onFormatChanged;
  final ValueChanged<String> onBitrateChanged;
  final VoidCallback onStartConversion;

  const LocalConversionCard({
    super.key,
    required this.isDesktop,
    required this.selectedFilePath,
    required this.targetFormat,
    required this.targetBitrate,
    required this.isConverting,
    required this.ffmpegAvailable,
    required this.onPickFile,
    required this.onFormatChanged,
    required this.onBitrateChanged,
    required this.onStartConversion,
  });

  @override
  Widget build(BuildContext context) {
    final isAudio = FFmpegService.audioFormats.contains(targetFormat);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Converter Arquivo Local',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Seleção de Arquivo
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      selectedFilePath != null
                          ? p.basename(selectedFilePath!)
                          : 'Nenhum arquivo selecionado...',
                      style: TextStyle(
                        color: selectedFilePath != null
                            ? Theme.of(context).textTheme.bodyMedium?.color
                            : Theme.of(context).hintColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: onPickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Selecionar'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Formatos de Saída
            const Text('Formato de Destino:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...FFmpegService.audioFormats.map((fmt) {
                  return ChoiceChip(
                    label: Text('🎵 ${fmt.toUpperCase()}'),
                    selected: targetFormat == fmt,
                    onSelected: (val) {
                      if (val) onFormatChanged(fmt);
                    },
                  );
                }),
                ...FFmpegService.videoFormats.map((fmt) {
                  return ChoiceChip(
                    label: Text('🎬 ${fmt.toUpperCase()}'),
                    selected: targetFormat == fmt,
                    onSelected: (val) {
                      if (val) onFormatChanged(fmt);
                    },
                  );
                }),
              ],
            ),
            if (isAudio && (targetFormat == 'mp3' || targetFormat == 'aac' || targetFormat == 'm4a')) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Qualidade de Áudio: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: targetBitrate,
                    items: FFmpegService.audioBitrates.map((b) {
                      return DropdownMenuItem(value: b, child: Text('$b (kbps)'));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) onBitrateChanged(v);
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: (selectedFilePath != null && !isConverting && ffmpegAvailable)
                    ? onStartConversion
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(isConverting ? 'Convertendo...' : 'Iniciar Conversão'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

