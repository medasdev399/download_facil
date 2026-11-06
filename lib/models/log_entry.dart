import 'package:flutter/material.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? details;
  final String? stackTrace;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.details,
    this.stackTrace,
  });

  String get levelLabel {
    switch (level) {
      case LogLevel.error:
        return 'ERRO';
      case LogLevel.warning:
        return 'ALERTA';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.debug:
        return 'DEBUG';
    }
  }

  Color get levelColor {
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFFF5252);
      case LogLevel.warning:
        return const Color(0xFFFFAB40);
      case LogLevel.info:
        return const Color(0xFF40C4FF);
      case LogLevel.debug:
        return const Color(0xFF90A4AE);
    }
  }

  IconData get levelIcon {
    switch (level) {
      case LogLevel.error:
        return Icons.error_outline_rounded;
      case LogLevel.warning:
        return Icons.warning_amber_rounded;
      case LogLevel.info:
        return Icons.info_outline_rounded;
      case LogLevel.debug:
        return Icons.bug_report_outlined;
    }
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write('[$formattedTime] [${levelLabel.padRight(6)}] [$tag] $message');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\nDetalhes:\n$details');
    }
    if (stackTrace != null && stackTrace!.trim().isNotEmpty) {
      buffer.write('\nStack trace:\n$stackTrace');
    }
    return buffer.toString();
  }
}

