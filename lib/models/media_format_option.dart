enum MediaCategory { video, audio }

class MediaFormatOption {
  final String label; // Ex: "1080p (Full HD)", "720p (HD)", "MP3 - 320 kbps"
  final String extension; // "mp4", "mp3", "m4a", "mkv", "webm", etc.
  final MediaCategory category; // video ou audio
  final String? qualityTag; // "1080p", "720p", "320k", etc.
  final int? totalBytes; // tamanho em bytes se conhecido
  final String? codecInfo; // "H.264", "VP9", "AAC", "MP3"
  final String? streamId; // id ou tag do stream
  final dynamic rawStreamInfo; // streamInfo se for do youtube_explode
  final Map<String, String>? httpHeaders; // Cabeçalhos HTTP necessários (ex: Referer, User-Agent)

  const MediaFormatOption({
    required this.label,
    required this.extension,
    required this.category,
    this.qualityTag,
    this.totalBytes,
    this.codecInfo,
    this.streamId,
    this.rawStreamInfo,
    this.httpHeaders,
  });

  String get formattedSize {
    if (totalBytes == null || totalBytes! <= 0) return '';
    final mb = totalBytes! / (1024 * 1024);
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class DetectedMediaInfo {
  final String url;
  final String title;
  final String? author;
  final Duration? duration;
  final String? thumbnailUrl;
  final List<MediaFormatOption> videoFormats;
  final List<MediaFormatOption> audioFormats;
  final bool isYouTube;

  const DetectedMediaInfo({
    required this.url,
    required this.title,
    this.author,
    this.duration,
    this.thumbnailUrl,
    required this.videoFormats,
    required this.audioFormats,
    this.isYouTube = false,
  });

  String get formattedDuration {
    if (duration == null) return '';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  int get totalOptionsCount => videoFormats.length + audioFormats.length;
}

