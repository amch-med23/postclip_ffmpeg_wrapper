import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

/// A controller to manage FFmpeg conversion
class FFmpegConversionController {
  FFmpegSession? _session;
  bool get isRunning => _session != null;

  /// Aborts any ongoing conversion
  Future<void> abort() async {
    final session = _session;
    if (session != null) {
      await FFmpegKit.cancel(session.getSessionId());
      _session = null;
    }
  }
}

/// Converts media to: MP4, MOV, MP3, WAV, AAC, FLAC.
Future<bool> convertMedia({
  required String inputPath,
  required String outputPath,
  required String format,
  required String quality,
  Function(double)? onProgress,
  FFmpegConversionController? controller,
}) async {
  final lowerFormat = format.toLowerCase();
  final isAudioFormat = ['mp3', 'wav', 'aac', 'flac'].contains(lowerFormat);
  final isVideoFormat = ['mp4', 'mov'].contains(lowerFormat);

  if (!isAudioFormat && !isVideoFormat) {
    throw UnsupportedError("Unsupported format: $format");
  }

  final inputIsVideo = _isVideoFile(inputPath);

  late String cmd;

  if (!inputIsVideo && isAudioFormat) {
    cmd = _buildAudioCommand(inputPath, outputPath, quality, lowerFormat);
  } else if (inputIsVideo && isAudioFormat) {
    cmd = _buildVideoToAudioCommand(inputPath, outputPath, quality, lowerFormat);
  } else if (inputIsVideo && isVideoFormat) {
    cmd = _buildVideoCommand(inputPath, outputPath, quality);
  } else {
    throw UnsupportedError("Unsupported conversion from this type to $format");
  }

  // Get duration for progress calculation
  Duration? totalDuration;
  try {
    totalDuration = await _getMediaDuration(inputPath);
  } catch (e) {
    // If we can't get duration, progress won't work but conversion can still proceed
    print("Could not determine media duration: $e");
  }

  // Start the conversion asynchronously
  final session = await FFmpegKit.executeAsync(cmd);

  controller?._session = session;

  // Poll for progress if we have a duration and callback
  Timer? progressTimer;
  if (totalDuration != null && onProgress != null) {
    progressTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      try {
        final statistics = await session.getAllStatistics();
        if (statistics.isNotEmpty) {
          final lastStat = statistics.last;
          final time = lastStat.getTime();
          if (time > 0) {
            final currentMs = time.toDouble();
            final totalMs = totalDuration!.inMilliseconds.toDouble();
            final progress = (currentMs / totalMs).clamp(0.0, 1.0);
            onProgress(progress);
          }
        }
      } catch (e) {
        // Ignore errors during progress polling
      }
    });
  }

  // Wait for the session to complete
  final returnCode = await session.getReturnCode();

  // Stop progress polling
  progressTimer?.cancel();

  // Final progress update
  if (onProgress != null && ReturnCode.isSuccess(returnCode)) {
    onProgress(1.0);
  }

  // Check if successful
  final success = ReturnCode.isSuccess(returnCode);

  return success;
}

/// Get the duration of a media file using ffprobe
Future<Duration?> _getMediaDuration(String filePath) async {
  try {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final information = session.getMediaInformation();

    if (information == null) return null;

    final durationString = information.getDuration();
    if (durationString == null || durationString.isEmpty) return null;

    final durationSeconds = double.tryParse(durationString);
    if (durationSeconds == null) return null;

    return Duration(milliseconds: (durationSeconds * 1000).round());
  } catch (e) {
    print("Error getting media duration: $e");
    return null;
  }
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
    case 'mp3':
      return 'libmp3lame';
    case 'aac':
      return 'aac';
    case 'flac':
      return 'flac';
    case 'wav':
      return 'pcm_s16le';
    default:
      throw UnsupportedError("Unsupported audio format: $format");
  }
}

int _getCRF(String quality) {
  switch (quality.toLowerCase()) {
    case 'low':
      return 35;
    case 'medium':
      return 28;
    case 'high':
      return 20;
    default:
      return 28;
  }
}

int _getAudioQScale(String quality) {
  switch (quality.toLowerCase()) {
    case 'low':
      return 7;
    case 'medium':
      return 5;
    case 'high':
      return 2;
    default:
      return 5;
  }
}