import 'package:dio/dio.dart';

enum DownloadStatus { pending, downloading, converting, paused, completed, failed, canceled }

enum DownloadMediaType { general, video, music }

class DownloadItem {
  final String id;
  final String url;
  String fileName;
  String savePath;
  int downloadedBytes;
  int totalBytes;
  double speedBytesPerSec;
  DownloadStatus status;
  DownloadMediaType mediaType;
  CancelToken? cancelToken;
  String? errorMessage;
  String? thumbnailUrl;
  String? author;
  Duration? duration;
  String? quality;
  String? statusMessage;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.status = DownloadStatus.pending,
    this.mediaType = DownloadMediaType.general,
    this.cancelToken,
    this.errorMessage,
    this.thumbnailUrl,
    this.author,
    this.duration,
    this.quality,
    this.statusMessage,
  });

  double get progress => totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  String get formattedDuration {
    if (duration == null) return '';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '0 B/s';
    const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var i = 0;
    double speed = speedBytesPerSec;
    while (speed >= 1024 && i < suffixes.length - 1) {
      speed /= 1024;
      i++;
    }
    return '${speed.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
