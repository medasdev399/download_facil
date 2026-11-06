enum ConversionStatus { pending, converting, completed, failed }

class ConversionItem {
  final String id;
  final String inputPath;
  final String outputPath;
  final String inputFileName;
  final String outputFileName;
  final String targetFormat;
  final String audioBitrate;
  ConversionStatus status;
  double progress;
  String? errorMessage;

  ConversionItem({
    required this.id,
    required this.inputPath,
    required this.outputPath,
    required this.inputFileName,
    required this.outputFileName,
    required this.targetFormat,
    this.audioBitrate = '192k',
    this.status = ConversionStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
  });
}

