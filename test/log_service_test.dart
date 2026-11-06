import 'package:flutter_test/flutter_test.dart';
import 'package:download_facil/models/log_entry.dart';
import 'package:download_facil/services/log_service.dart';

void main() {
  setUp(() {
    LogService.clear();
  });

  group('LogService & LogEntry', () {
    test('records info, warning and error logs', () {
      LogService.info('Mensagem informativa', tag: 'Teste');
      LogService.warning('Mensagem de alerta', tag: 'Teste');
      LogService.error('Mensagem de erro', tag: 'Teste', error: 'Exceção simulada');

      final logs = LogService.logsNotifier.value;
      // Note que o clear adiciona uma mensagem inicial "Logs reinicializados pelo usuário."
      expect(logs.any((l) => l.message == 'Mensagem informativa' && l.level == LogLevel.info), isTrue);
      expect(logs.any((l) => l.message == 'Mensagem de alerta' && l.level == LogLevel.warning), isTrue);
      expect(logs.any((l) => l.message == 'Mensagem de erro' && l.level == LogLevel.error), isTrue);
      expect(LogService.errorCountNotifier.value, equals(1));
      expect(LogService.warningCountNotifier.value, equals(1));
    });

    test('formats log entry as readable text', () {
      final entry = LogEntry(
        id: '123',
        timestamp: DateTime(2026, 11, 6, 15, 30, 45, 120),
        level: LogLevel.error,
        tag: 'FFmpeg',
        message: 'Falha no processo',
        details: 'Código de saída 1',
        stackTrace: 'Stacktrace simulada',
      );

      final formatted = entry.toFormattedString();
      expect(formatted, contains('[15:30:45.120]'));
      expect(formatted, contains('[ERRO  ]'));
      expect(formatted, contains('[FFmpeg]'));
      expect(formatted, contains('Falha no processo'));
      expect(formatted, contains('Código de saída 1'));
      expect(formatted, contains('Stacktrace simulada'));
    });

    test('exportAll outputs non-empty text when logs exist', () {
      LogService.error('Erro crítico no download', tag: 'Download');
      final export = LogService.exportAll();
      expect(export, contains('Erro crítico no download'));
      expect(export, contains('[Download]'));
    });

    test('clears logs and resets error counters', () {
      LogService.error('Erro 1', tag: 'Teste');
      LogService.error('Erro 2', tag: 'Teste');
      expect(LogService.errorCountNotifier.value, equals(2));

      LogService.clear();
      expect(LogService.errorCountNotifier.value, equals(0));
      expect(LogService.warningCountNotifier.value, equals(0));
    });
  });
}

