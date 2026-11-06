import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/download_item.dart';
import '../../models/media_format_option.dart';
import '../../services/storage_resolver.dart';

class MediaFormatSelectionResult {
  final DownloadMediaType mediaType;
  final MediaFormatOption option;
  final String fileName;
  final String savePath;

  const MediaFormatSelectionResult({
    required this.mediaType,
    required this.option,
    required this.fileName,
    required this.savePath,
  });
}

class MediaFormatSelectorDialog extends StatefulWidget {
  final DetectedMediaInfo mediaInfo;
  final String? defaultDirectory;

  const MediaFormatSelectorDialog({
    super.key,
    required this.mediaInfo,
    this.defaultDirectory,
  });

  static Future<MediaFormatSelectionResult?> show(
    BuildContext context, {
    required DetectedMediaInfo mediaInfo,
    String? defaultDirectory,
  }) {
    return showModalBottomSheet<MediaFormatSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MediaFormatSelectorDialog(
        mediaInfo: mediaInfo,
        defaultDirectory: defaultDirectory,
      ),
    );
  }

  @override
  State<MediaFormatSelectorDialog> createState() => _MediaFormatSelectorDialogState();
}

class _MediaFormatSelectorDialogState extends State<MediaFormatSelectorDialog> {
  late MediaCategory _selectedCategory;
  MediaFormatOption? _selectedOption;
  late String _directory;
  late TextEditingController _fileNameController;

  @override
  void initState() {
    super.initState();
    // Inicia com Vídeo se disponível, senão Áudio
    if (widget.mediaInfo.videoFormats.isNotEmpty) {
      _selectedCategory = MediaCategory.video;
      _selectedOption = widget.mediaInfo.videoFormats.first;
    } else {
      _selectedCategory = MediaCategory.audio;
      _selectedOption = widget.mediaInfo.audioFormats.isNotEmpty
          ? widget.mediaInfo.audioFormats.first
          : null;
    }

    _directory = widget.defaultDirectory ?? '';
    final initialName = _sanitizeFileName(widget.mediaInfo.title);
    final ext = _selectedOption?.extension ?? (_selectedCategory == MediaCategory.video ? 'mp4' : 'mp3');
    _fileNameController = TextEditingController(text: '$initialName.$ext');
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  void _onCategoryChanged(MediaCategory cat) {
    setState(() {
      _selectedCategory = cat;
      if (cat == MediaCategory.video) {
        _selectedOption = widget.mediaInfo.videoFormats.isNotEmpty
            ? widget.mediaInfo.videoFormats.first
            : null;
      } else {
        _selectedOption = widget.mediaInfo.audioFormats.isNotEmpty
            ? widget.mediaInfo.audioFormats.first
            : null;
      }
      _updateFileName();
    });
  }

  void _onOptionSelected(MediaFormatOption opt) {
    setState(() {
      _selectedOption = opt;
      _updateFileName();
    });
  }

  void _updateFileName() {
    if (_selectedOption == null) return;
    final base = p.withoutExtension(_fileNameController.text.trim());
    final safeBase = base.isNotEmpty ? base : _sanitizeFileName(widget.mediaInfo.title);
    _fileNameController.text = '$safeBase.${_selectedOption!.extension}';
  }

  Future<void> _pickDirectory() async {
    final picked = await StorageResolver.pickCustomDirectory();
    if (picked != null && mounted) {
      setState(() {
        _directory = picked;
      });
    }
  }

  Future<void> _confirmDownload() async {
    if (_selectedOption == null) return;

    final name = _fileNameController.text.trim();
    final safeName = name.isNotEmpty
        ? name
        : '${_sanitizeFileName(widget.mediaInfo.title)}.${_selectedOption!.extension}';

    String fullPath;
    if (_directory.isNotEmpty) {
      fullPath = p.join(_directory, safeName);
    } else {
      fullPath = await StorageResolver.getDefaultSavePath(safeName);
    }

    if (!mounted) return;

    Navigator.of(context).pop(MediaFormatSelectionResult(
      mediaType: _selectedCategory == MediaCategory.video
          ? DownloadMediaType.video
          : DownloadMediaType.music,
      option: _selectedOption!,
      fileName: safeName,
      savePath: fullPath,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        maxWidth: 720,
      ),
      margin: isDesktop ? const EdgeInsets.all(24) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: isDesktop
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de arraste no mobile
          if (!isDesktop)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

          // Cabeçalho com Título e Fechar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Icon(Icons.video_library_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Opções de Download de Mídia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Conteúdo rolável
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card com informações da mídia (Thumbnail, Título, Autor, Duração)
                  _buildMediaInfoCard(theme, colorScheme),
                  const SizedBox(height: 18),

                  // Segmented Button para Tipo: Vídeo vs Áudio
                  SegmentedButton<MediaCategory>(
                    segments: [
                      ButtonSegment(
                        value: MediaCategory.video,
                        icon: const Icon(Icons.videocam_rounded),
                        label: Text('Vídeo (${widget.mediaInfo.videoFormats.length})'),
                        enabled: widget.mediaInfo.videoFormats.isNotEmpty,
                      ),
                      ButtonSegment(
                        value: MediaCategory.audio,
                        icon: const Icon(Icons.music_note_rounded),
                        label: Text('Áudio / Música (${widget.mediaInfo.audioFormats.length})'),
                        enabled: widget.mediaInfo.audioFormats.isNotEmpty,
                      ),
                    ],
                    selected: {_selectedCategory},
                    onSelectionChanged: (set) => _onCategoryChanged(set.first),
                  ),
                  const SizedBox(height: 16),

                  // Lista de formatos e resoluções
                  Text(
                    _selectedCategory == MediaCategory.video
                        ? 'Selecione a Resolução e Qualidade do Vídeo:'
                        : 'Selecione o Formato e Qualidade do Áudio:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 10),

                  _buildFormatOptionsList(colorScheme),
                  const SizedBox(height: 20),

                  // Nome do arquivo
                  TextField(
                    controller: _fileNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do arquivo de destino',
                      prefixIcon: Icon(Icons.drive_file_rename_outline),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Pasta de destino
                  InkWell(
                    onTap: _pickDirectory,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_open, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Salvar em:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(
                                  _directory.isNotEmpty ? _directory : 'Pasta padrão do sistema',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Rodapé com Botão de Ação
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _selectedOption != null ? _confirmDownload : null,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _selectedOption != null
                      ? 'Baixar Agora (${_selectedOption!.label})'
                      : 'Selecione uma opção',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaInfoCard(ThemeData theme, ColorScheme colorScheme) {
    final thumb = widget.mediaInfo.thumbnailUrl;
    final dur = widget.mediaInfo.formattedDuration;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumb != null && thumb.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.network(
                    thumb,
                    width: 110,
                    height: 68,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 110,
                      height: 68,
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.play_circle_outline, size: 36),
                    ),
                  ),
                  if (dur.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dur,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.play_circle_fill, size: 40, color: colorScheme.onPrimaryContainer),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mediaInfo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                if (widget.mediaInfo.author != null)
                  Text(
                    widget.mediaInfo.author!,
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.mediaInfo.isYouTube ? 'YouTube' : 'Web Stream',
                    style: TextStyle(color: colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatOptionsList(ColorScheme colorScheme) {
    final list = _selectedCategory == MediaCategory.video
        ? widget.mediaInfo.videoFormats
        : widget.mediaInfo.audioFormats;

    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: const Text('Nenhuma opção compatível nesta categoria.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final opt = list[index];
        final isSelected = _selectedOption == opt;

        return Material(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _onOptionSelected(opt),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: isSelected ? 1.8 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? colorScheme.primary : colorScheme.outline,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        if (opt.codecInfo != null)
                          Text(
                            'Codec: ${opt.codecInfo}',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      opt.extension.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  if (opt.formattedSize.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        opt.formattedSize,
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

