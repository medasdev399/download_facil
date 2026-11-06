import 'package:flutter/material.dart';
import '../../models/download_item.dart';
import '../../services/ffmpeg_service.dart';

class ConvertDialogResult {
  final String targetFormat;
  final String audioBitrate;

  const ConvertDialogResult({
    required this.targetFormat,
    required this.audioBitrate,
  });
}

class ConvertMediaDialog extends StatefulWidget {
  final DownloadItem item;

  const ConvertMediaDialog({
    super.key,
    required this.item,
  });

  static Future<ConvertDialogResult?> show(BuildContext context, DownloadItem item) {
    return showDialog<ConvertDialogResult>(
      context: context,
      builder: (ctx) => ConvertMediaDialog(item: item),
    );
  }

  @override
  State<ConvertMediaDialog> createState() => _ConvertMediaDialogState();
}

class _ConvertMediaDialogState extends State<ConvertMediaDialog> {
  String _selectedFmt = 'mp3';
  String _selectedBit = '192k';

  @override
  Widget build(BuildContext context) {
    final isAudio = FFmpegService.audioFormats.contains(_selectedFmt);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.transform_rounded),
          SizedBox(width: 8),
          Text('Converter Arquivo'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Origem: ${widget.item.fileName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Formato Desejado:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...FFmpegService.audioFormats.map((fmt) {
                  return ChoiceChip(
                    label: Text('🎵 ${fmt.toUpperCase()}'),
                    selected: _selectedFmt == fmt,
                    onSelected: (val) {
                      if (val) setState(() => _selectedFmt = fmt);
                    },
                  );
                }),
                ...FFmpegService.videoFormats.map((fmt) {
                  return ChoiceChip(
                    label: Text('🎬 ${fmt.toUpperCase()}'),
                    selected: _selectedFmt == fmt,
                    onSelected: (val) {
                      if (val) setState(() => _selectedFmt = fmt);
                    },
                  );
                }),
              ],
            ),
            if (isAudio && (_selectedFmt == 'mp3' || _selectedFmt == 'aac' || _selectedFmt == 'm4a')) ...[
              const SizedBox(height: 14),
              const Text(
                'Qualidade de Áudio (Bitrate):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              DropdownButton<String>(
                value: _selectedBit,
                isExpanded: true,
                items: FFmpegService.audioBitrates.map((b) {
                  return DropdownMenuItem(value: b, child: Text('$b (kbps)'));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedBit = v);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Iniciar Conversão'),
          onPressed: () {
            Navigator.pop(
              context,
              ConvertDialogResult(
                targetFormat: _selectedFmt,
                audioBitrate: _selectedBit,
              ),
            );
          },
        ),
      ],
    );
  }
}

