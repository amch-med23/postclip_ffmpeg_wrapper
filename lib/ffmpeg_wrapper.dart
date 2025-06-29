import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';

/// Converts media to: MP4, MOV, MP3, WAV, AAC, FLAC.
/// Supports: video-to-video, audio-to-audio, and video-to-audio.
Future<bool> convertMedia({
  required String inputPath,
  required String outputPath,
  required String format,
  required String quality,
}) async {
  final lowerFormat = format.toLowerCase();
  final isAudioFormat = ['mp3', 'wav', 'aac', 'flac'].contains(lowerFormat);
  final isVideoFormat = ['mp4', 'mov'].contains(lowerFormat);

  if (!isAudioFormat && !isVideoFormat) {
    throw UnsupportedError("Unsupported format: $format");
  }

  final inputIsVideo = _isVideoFile(inputPath);
  final inputIsAudio = !inputIsVideo;

  late String cmd;

  if (inputIsAudio && isAudioFormat) {
    // audio-to-audio
    cmd = _buildAudioCommand(inputPath, outputPath, quality, lowerFormat);
  } else if (inputIsVideo && isAudioFormat) {
    // video-to-audio
    cmd = _buildVideoToAudioCommand(inputPath, outputPath, quality, lowerFormat);
  } else if (inputIsVideo && isVideoFormat) {
    // video-to-video
    cmd = _buildVideoCommand(inputPath, outputPath, quality);
  } else {
    throw UnsupportedError("Unsupported conversion from this type to $format");
  }

  final session = await FFmpegKit.execute(cmd);
  final returnCode = await session.getReturnCode();

  return returnCode.isValueSuccess();
}

bool _isVideoFile(String path) {
  final ext = path.split('.').last.toLowerCase();
  return ['mp4', 'mov', 'mkv', 'avi', 'webm'].contains(ext);
}

String _buildVideoCommand(String input, String output, String quality) {
  final crf = _getCRF(quality);
  return '-i "$input" -c:v libx264 -crf $crf -preset ultrafast -c:a copy "$output"';
}

String _buildVideoToAudioCommand(String input, String output, String quality, String format) {
  final qscale = _getAudioQScale(quality);
  final codec = _getAudioCodec(format);

  return '-i "$input" -vn -c:a $codec -qscale:a $qscale "$output"';
}

String _buildAudioCommand(String input, String output, String quality, String format) {
  final qscale = _getAudioQScale(quality);
  final codec = _getAudioCodec(format);

  return '-i "$input" -c:a $codec -qscale:a $qscale "$output"';
}

String _getAudioCodec(String format) {
  switch (format) {
    case 'mp3': return 'libmp3lame';
    case 'aac': return 'aac';
    case 'flac': return 'flac';
    case 'wav': return 'pcm_s16le';
    default: throw UnsupportedError("Unsupported audio format: $format");
  }
}

int _getCRF(String quality) {
  switch (quality.toLowerCase()) {
    case 'low': return 35;
    case 'medium': return 28;
    case 'high': return 20;
    default: return 28;
  }
}

int _getAudioQScale(String quality) {
  switch (quality.toLowerCase()) {
    case 'low': return 7;
    case 'medium': return 5;
    case 'high': return 2;
    default: return 5;
  }
}
