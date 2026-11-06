import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'log_service.dart';

class StorageResolver {
  /// Retorna o caminho completo seguro para salvar o arquivo em qualquer plataforma nativa
  static Future<String> getDefaultSavePath(String fileName) async {
    if (kIsWeb) return fileName; // Na Web o navegador gerencia o caminho

    Directory? baseDir;

    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        baseDir = await getDownloadsDirectory();
      } else if (Platform.isAndroid) {
        // Diretório externo visível pelo app no Android sem exigir MANAGE_EXTERNAL_STORAGE
        baseDir = await getExternalStorageDirectory();
      }
    } catch (e) {
      LogService.warning('Não foi possível obter pasta padrão de downloads: $e', tag: 'Storage');
      baseDir = null;
    }

    try {
      baseDir ??= await getApplicationDocumentsDirectory();
    } catch (e) {
      LogService.warning('Não foi possível obter pasta de documentos: $e', tag: 'Storage');
      baseDir = null;
    }

    if (baseDir != null) {
      final path = p.join(baseDir.path, fileName);
      LogService.debug('Caminho de salvamento resolvido: $path', tag: 'Storage');
      return path;
    }
    return fileName;
  }

  /// Permite ao usuário escolher outra pasta (Desktop e Android suportados)
  static Future<String?> pickCustomDirectory() async {
    if (kIsWeb) return null;
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Escolha onde salvar o arquivo',
      );
      if (selected != null) {
        LogService.info('Pasta de destino personalizada definida: $selected', tag: 'Storage');
      }
      return selected;
    } catch (e, stack) {
      LogService.error(
        'Erro ao selecionar pasta personalizada: $e',
        tag: 'Storage',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Permite selecionar um arquivo de mídia no computador para conversão
  static Future<String?> pickMediaFile() async {
    if (kIsWeb) return null;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', 'm4v',
          'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'wma',
        ],
        dialogTitle: 'Selecione um arquivo de vídeo ou áudio para conversão',
      );
      if (result.isEmpty) return null;
      final selectedPath = result.first.path;
      LogService.info('Arquivo selecionado para conversão: $selectedPath', tag: 'Storage');
      return selectedPath;
    } catch (e, stack) {
      LogService.error(
        'Erro ao selecionar arquivo de mídia: $e',
        tag: 'Storage',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Abre o arquivo no reprodutor padrão do sistema operacional
  static Future<void> openFile(String filePath) async {
    if (kIsWeb) return;
    try {
      LogService.info('Tentando abrir arquivo no sistema: $filePath', tag: 'Storage');
      if (Platform.isLinux) {
        await Process.run('xdg-open', [filePath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', [filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      }
    } catch (e, stack) {
      LogService.error(
        'Falha ao abrir arquivo "$filePath": $e',
        tag: 'Storage',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Abre a pasta no explorador de arquivos do sistema operacional
  static Future<void> openDirectory(String folderPath) async {
    if (kIsWeb) return;
    try {
      LogService.info('Abrindo pasta no gerenciador de arquivos: $folderPath', tag: 'Storage');
      if (Platform.isLinux) {
        await Process.run('xdg-open', [folderPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', [folderPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      }
    } catch (e, stack) {
      LogService.error(
        'Falha ao abrir pasta "$folderPath": $e',
        tag: 'Storage',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
