import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/log_entry.dart';
import '../../services/log_service.dart';

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  /// Abre a caixa de diálogo de logs responsiva
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const LogViewerDialog(),
    );
  }

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final TextEditingController _searchController = TextEditingController();
  LogLevel? _selectedLevelFilter; // null = Todos
  bool _newestFirst = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyAllLogs(BuildContext context) {
    final text = LogService.exportAll();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Todos os logs foram copiados para a área de transferência!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copySingleLog(BuildContext context, LogEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Log [${entry.tag}] copiado!'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  List<LogEntry> _filterLogs(List<LogEntry> allLogs) {
    final query = _searchController.text.trim().toLowerCase();

    return allLogs.where((entry) {
      if (_selectedLevelFilter != null && entry.level != _selectedLevelFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final inTag = entry.tag.toLowerCase().contains(query);
        final inMsg = entry.message.toLowerCase().contains(query);
        final inDetails = (entry.details ?? '').toLowerCase().contains(query);
        final inStack = (entry.stackTrace ?? '').toLowerCase().contains(query);
        if (!inTag && !inMsg && !inDetails && !inStack) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 700;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40 : 12,
        vertical: isDesktop ? 40 : 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 950,
          maxHeight: size.height * 0.9,
          minHeight: (size.height * 0.9 < 350) ? size.height * 0.9 : 350,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ValueListenableBuilder<List<LogEntry>>(
            valueListenable: LogService.logsNotifier,
            builder: (context, allLogs, _) {
              final errorCount = allLogs.where((l) => l.level == LogLevel.error).length;
              final warningCount = allLogs.where((l) => l.level == LogLevel.warning).length;
              final infoCount = allLogs.where((l) => l.level == LogLevel.info).length;
              final debugCount = allLogs.where((l) => l.level == LogLevel.debug).length;

              final filtered = _filterLogs(allLogs);
              final displayLogs = _newestFirst ? filtered.reversed.toList() : filtered;

              return SelectionArea(
                child: Scaffold(
                  backgroundColor: theme.scaffoldBackgroundColor,
                  appBar: AppBar(
                    titleSpacing: 16,
                    leading: const Icon(Icons.terminal_rounded),
                    title: Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Console de Logs & Diagnóstico',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (errorCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.redAccent, width: 1),
                            ),
                            child: Text(
                              '$errorCount erro${errorCount > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Copiar todos os logs',
                        icon: const Icon(Icons.copy_all_rounded),
                        onPressed: allLogs.isEmpty ? null : () => _copyAllLogs(context),
                      ),
                      IconButton(
                        tooltip: 'Limpar todos os logs',
                        icon: const Icon(Icons.delete_sweep_outlined),
                        onPressed: allLogs.isEmpty
                            ? null
                            : () {
                                LogService.clear();
                              },
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      // Barra de pesquisa e controles de filtro
                      _buildFilterControls(
                        allLogsCount: allLogs.length,
                        errorCount: errorCount,
                        warningCount: warningCount,
                        infoCount: infoCount,
                        debugCount: debugCount,
                      ),
                      const Divider(height: 1),
                      // Lista de logs em formato terminal
                      Expanded(
                        child: displayLogs.isEmpty
                            ? _buildEmptyState(allLogs.isEmpty)
                            : Container(
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF111318)
                                    : const Color(0xFFF0F4F8),
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: displayLogs.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final item = displayLogs[index];
                                    return _buildLogCard(item);
                                  },
                                ),
                              ),
                      ),
                      // Rodapé com resumo
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Exibindo ${displayLogs.length} de ${allLogs.length} registro${allLogs.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _newestFirst ? '▼ Mais recentes no topo' : '▲ Mais antigos no topo',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilterControls({
    required int allLogsCount,
    required int errorCount,
    required int warningCount,
    required int infoCount,
    required int debugCount,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      hintText: 'Filtrar por mensagem, tag, URL ou stack trace...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: _newestFirst ? 'Inverter: Mais antigos no topo' : 'Inverter: Mais recentes no topo',
                icon: Icon(
                  _newestFirst ? Icons.south_rounded : Icons.north_rounded,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _newestFirst = !_newestFirst;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('Todos ($allLogsCount)'),
                  selected: _selectedLevelFilter == null,
                  onSelected: (val) {
                    if (val) setState(() => _selectedLevelFilter = null);
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  avatar: const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent),
                  label: Text('Erros ($errorCount)'),
                  selected: _selectedLevelFilter == LogLevel.error,
                  selectedColor: Colors.redAccent.withValues(alpha: 0.2),
                  onSelected: (val) {
                    setState(() => _selectedLevelFilter = val ? LogLevel.error : null);
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orangeAccent),
                  label: Text('Avisos ($warningCount)'),
                  selected: _selectedLevelFilter == LogLevel.warning,
                  selectedColor: Colors.orangeAccent.withValues(alpha: 0.2),
                  onSelected: (val) {
                    setState(() => _selectedLevelFilter = val ? LogLevel.warning : null);
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  avatar: const Icon(Icons.info_outline_rounded, size: 16, color: Colors.lightBlueAccent),
                  label: Text('Info ($infoCount)'),
                  selected: _selectedLevelFilter == LogLevel.info,
                  selectedColor: Colors.lightBlueAccent.withValues(alpha: 0.2),
                  onSelected: (val) {
                    setState(() => _selectedLevelFilter = val ? LogLevel.info : null);
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  avatar: const Icon(Icons.bug_report_outlined, size: 16, color: Colors.blueGrey),
                  label: Text('Debug ($debugCount)'),
                  selected: _selectedLevelFilter == LogLevel.debug,
                  onSelected: (val) {
                    setState(() => _selectedLevelFilter = val ? LogLevel.debug : null);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool noLogsEver) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                noLogsEver ? Icons.receipt_long_outlined : Icons.filter_alt_off_outlined,
                size: 48,
                color: Colors.grey.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                noLogsEver ? 'Nenhum evento registrado ainda' : 'Nenhum log corresponde ao filtro atual',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                noLogsEver
                    ? 'Os logs de downloads, YouTube, FFmpeg e rede aparecerão aqui.'
                    : 'Tente alterar o filtro ou o termo de pesquisa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(LogEntry item) {
    final theme = Theme.of(context);
    final hasDetails = (item.details != null && item.details!.isNotEmpty) ||
        (item.stackTrace != null && item.stackTrace!.isNotEmpty);

    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E212B) : Colors.white;

    final titleWidget = Row(
      children: [
        // Badge de hora
        Text(
          item.formattedTime,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
        const SizedBox(width: 8),
        // Tag badge
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: item.levelColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.tag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: item.levelColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Nível badge
        Text(
          '[${item.levelLabel}]',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: item.levelColor,
          ),
        ),
      ],
    );

    final subtitleWidget = Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        item.message,
        style: TextStyle(
          fontSize: 13,
          color: item.level == LogLevel.error
              ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
    );

    return Material(
      color: cardBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: item.level == LogLevel.error
              ? Colors.redAccent.withValues(alpha: 0.4)
              : (item.level == LogLevel.warning
                  ? Colors.orangeAccent.withValues(alpha: 0.3)
                  : theme.dividerColor.withValues(alpha: 0.4)),
          width: 1,
        ),
      ),
      child: !hasDetails
          ? ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Icon(
                item.levelIcon,
                color: item.levelColor,
                size: 20,
              ),
              title: titleWidget,
              subtitle: subtitleWidget,
              trailing: IconButton(
                tooltip: 'Copiar este log',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => _copySingleLog(context, item),
              ),
            )
          : Theme(
              // Remove linha divisória padrão do ExpansionTile
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: Icon(
                  item.levelIcon,
                  color: item.levelColor,
                  size: 20,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copiar este log',
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () => _copySingleLog(context, item),
                    ),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
                title: titleWidget,
                subtitle: subtitleWidget,
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F1117) : const Color(0xFF21252B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.details != null && item.details!.isNotEmpty) ...[
                          const Text(
                            'Detalhes:',
                            style: TextStyle(
                              color: Color(0xFFE5C07B),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.details!,
                            style: const TextStyle(
                              color: Color(0xFFABB2BF),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        if (item.stackTrace != null && item.stackTrace!.isNotEmpty) ...[
                          if (item.details != null && item.details!.isNotEmpty)
                            const Divider(color: Colors.white24, height: 16),
                          const Text(
                            'Stack Trace:',
                            style: TextStyle(
                              color: Color(0xFFE06C75),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.stackTrace!,
                            style: const TextStyle(
                              color: Color(0xFFABB2BF),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

