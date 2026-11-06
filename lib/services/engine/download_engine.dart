import '../../models/download_item.dart';
import 'io_download_engine.dart' if (dart.library.html) 'web_download_engine.dart';

abstract class DownloadEngine {
  factory DownloadEngine() => createEngine();

  Future<void> startOrResume(DownloadItem item, {required void Function() onUpdate});
  void pause(DownloadItem item);
}