import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';

/// Converts media using FFmpeg
/// [inputPath]: source file path
/// [outputPath]: desired output path
/// [quality]: "Low", "Medium", or "High"
Future<bool> convertMedia({
  required String inputPath,
  required String outputPath,
  required String quality,
}) async {
  final crf = _getCRF(quality);
  final cmd = "-i \"$inputPath\" -c:v libx264 -crf $crf -preset ultrafast \"$outputPath\"";

  final session = await FFmpegKit.execute(cmd);
  final code = await session.getReturnCode();
  return code.isValueSuccess();
}

int _getCRF(String quality) {
  switch (quality.toLowerCase()) {
    case 'low': return 35;
    case 'medium': return 28;
    case 'high': return 20;
    default: return 28;
  }
}
