import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart';


/// Converts media to: MP4, MOV, MP3, WAV, AAC, FLAC.
/// Supports: video-to-video, audio-to-audio, and video-to-audio.
Future<bool> convertMedia({
  required String inputPath,
  required String outputPath,
  required String format,
  required String quality,
  Function(double) ? onProgress,
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
  // Estimate total duration
  /*Duration? totalDuration;
  await FFmpegKit.executeAsync(
    '-i "$inputPath"',
    completeCallback: (_) {},
    logCallback: (log) {
      if (log.getMessage().contains("Duration:")) {
        final regex = RegExp(r'Duration: (\d+):(\d+):(\d+).(\d+)');
        final match = regex.firstMatch(log.getMessage());
        if (match != null) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final s = int.parse(match.group(3)!);
          totalDuration = Duration(hours: h, minutes: m, seconds: s);
        }
      }
    },
  ); */

  Duration? totalDuration;
  final sessionForDuration = await FFmpegKit.executeAsync(
    '-i "$inputPath"',
        (session) async {
      // This is the sessionCallback, called on completion of the session.
      // You could technically put the duration parsing here, but it's often more
      // reliable to rely on the logCallback which happens during execution.
    },
        (Log log) { // This is the LogCallback
      if (log.getMessage().contains("Duration:")) {
        final regex = RegExp(r'Duration: (\d+):(\d+):(\d+).(\d+)');
        final match = regex.firstMatch(log.getMessage());
        if (match != null) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final s = int.parse(match.group(3)!);
          totalDuration = Duration(hours: h, minutes: m, seconds: s);
        }
      }
    },
        (Statistics statistics) {
      // This is the StatisticsCallback, likely not relevant for simple duration estimation,
      // but must be provided if the method signature expects it.
    },
  );

  final session = await FFmpegKit.executeAsync(
    cmd,
    statisticsCallback: (stats) {
      if (totalDuration != null) {
        final time = Duration(milliseconds: stats.getTime());
        final ratio = time.inMilliseconds / totalDuration!.inMilliseconds;
        if (onProgress != null) onProgress(ratio.clamp(0.0, 1.0));
      }
    },
  );


  //final session = await FFmpegKit.execute(cmd);
  final returnCode = await session.getReturnCode();

  return returnCode?.isValueSuccess() ?? false;
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
