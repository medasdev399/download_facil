import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../models/log_entry.dart';

class LogService {
  static const int maxLogs = 500;

  static final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier<List<LogEntry>>([]);
  static final ValueNotifier<int> errorCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> warningCountNotifier = ValueNotifier<int>(0);

  /// Registra uma mensagem no sistema de logs
  static void log(
    LogLevel level,
    String message, {
    String tag = 'App',
    dynamic details,
    dynamic stackTrace,
  }) {
    final entry = LogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      details: details != null ? details.toString() : null,
      stackTrace: stackTrace != null ? stackTrace.toString() : null,
    );

    final current = List<LogEntry>.from(logsNotifier.value);
    current.add(entry);
    if (current.length > maxLogs) {
      current.removeAt(0);
    }

    void updateNotifiers() {
      logsNotifier.value = current;
      if (level == LogLevel.error) {
        errorCountNotifier.value++;
      } else if (level == LogLevel.warning) {
        warningCountNotifier.value++;
      }
    }

    // Se estivermos dentro da fase de build/layout/renderização do Flutter,
    // adia a notificação para após o frame para evitar:
    // "setState() or markNeedsBuild() called during build."
    final binding = WidgetsBinding.instance;
    final isPersistentPhase = binding.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        binding.schedulerPhase == SchedulerPhase.midFrameMicrotasks;

    if (isPersistentPhase) {
      binding.addPostFrameCallback((_) {
        updateNotifiers();
      });
    } else {
      updateNotifiers();
    }

    // Saída no console em ambiente de desenvolvimento
    if (kDebugMode) {
      debugPrint('[${entry.levelLabel}] [${entry.tag}] $message');
      if (entry.details != null) debugPrint('  ↳ Detalhes: ${entry.details}');
      if (entry.stackTrace != null) debugPrint('  ↳ StackTrace: ${entry.stackTrace}');
    }
  }

  static void info(String message, {String tag = 'App', dynamic details}) {
    log(LogLevel.info, message, tag: tag, details: details);
  }

  static void warning(String message, {String tag = 'App', dynamic details}) {
    log(LogLevel.warning, message, tag: tag, details: details);
  }

  static void error(
    String message, {
    String tag = 'App',
    dynamic error,
    dynamic stackTrace,
    dynamic details,
  }) {
    final List<String> detailParts = [];
    if (error != null) detailParts.add('Erro: $error');
    if (details != null) detailParts.add('Detalhes: $details');

    log(
      LogLevel.error,
      message,
      tag: tag,
      details: detailParts.isNotEmpty ? detailParts.join('\n') : null,
      stackTrace: stackTrace,
    );
  }

  static void debug(String message, {String tag = 'App', dynamic details}) {
    log(LogLevel.debug, message, tag: tag, details: details);
  }

  /// Limpa todos os logs acumulados
  static void clear() {
    void reset() {
      logsNotifier.value = [];
      errorCountNotifier.value = 0;
      warningCountNotifier.value = 0;
    }

    final binding = WidgetsBinding.instance;
    final isPersistentPhase = binding.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        binding.schedulerPhase == SchedulerPhase.midFrameMicrotasks;

    if (isPersistentPhase) {
      binding.addPostFrameCallback((_) {
        reset();
        info('Logs reinicializados pelo usuário.', tag: 'Sistema');
      });
    } else {
      reset();
      info('Logs reinicializados pelo usuário.', tag: 'Sistema');
    }
  }

  /// Exporta todos os logs formatados como texto legível para diagnóstico
  static String exportAll() {
    if (logsNotifier.value.isEmpty) {
      return 'Nenhum log registrado até o momento.';
    }
    return logsNotifier.value.map((e) => e.toFormattedString()).join('\n----------------------------------------\n');
  }

  /// Inicializa a captura global de exceções do Flutter e Dart
  static void initGlobalErrorHandling() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      final msg = details.exceptionAsString();
      // Evita loops recursivos caso ocorra erro no próprio mecanismo de build
      if (msg.contains('setState() or markNeedsBuild() called during build')) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        error(
          'Erro no Flutter Framework: $msg',
          tag: 'Flutter',
          details: details.context?.toString(),
          stackTrace: details.stack,
        );
      });
    };

    PlatformDispatcher.instance.onError = (Object errorObj, StackTrace stack) {
      error(
        'Exceção assíncrona não tratada: $errorObj',
        tag: 'Async',
        error: errorObj,
        stackTrace: stack,
      );
      return true;
    };

    info('Download Fácil iniciado. Monitoramento de logs ativo.', tag: 'Sistema');
  }
}

