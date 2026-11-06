import 'package:web/web.dart' as web;
import '../../models/download_item.dart';
import 'download_engine.dart';

DownloadEngine createEngine() => WebDownloadEngine();

class WebDownloadEngine implements DownloadEngine {
  @override
  Future<void> startOrResume(
    DownloadItem item, {
    required void Function() onUpdate,
  }) async {
    // Na Web, navegadores bloqueiam escrita em disco direto (.part) e sofrem com CORS em Streams.
    // Delegamos o fluxo para o gerenciador nativo do navegador via HTMLAnchorElement.
    item.status = DownloadStatus.downloading;
    onUpdate();

    final anchor = web.HTMLAnchorElement()
      ..href = item.url
      ..download = item.fileName
      ..target = '_blank';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();

    item.status = DownloadStatus.completed;
    onUpdate();
  }

  @override
  void pause(DownloadItem item) {
    // Gerenciado pelo navegador
  }
}