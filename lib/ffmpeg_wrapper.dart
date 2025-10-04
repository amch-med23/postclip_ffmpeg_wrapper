import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

/// A controller to manage FFmpeg conversion
class FFmpegConversionController {
  FFmpegSession? _session;
  bool _cancelled = false;
  bool get isRunning => _session != null;

  /// Aborts any ongoing conversion
  Future<void> abort() async {
    _cancelled = true;
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
    print("Could not determine media duration: $e");
  }

  // Reset cancelled flag
  if (controller != null) {
    controller._cancelled = false;
  }

  // Start the conversion
  final session = await FFmpegKit.execute(cmd);
  controller?._session = session;

  // Start progress polling if we have duration
  Timer? progressTimer;
  if (totalDuration != null && onProgress != null && controller != null) {
    final totalMs = totalDuration.inMilliseconds.toDouble();

    progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      // Stop if cancelled
      if (controller._cancelled) {
        timer.cancel();
        return;
      }

      try {
        final state = await session.getState();

        // Check if session is still running
        if (state.toString() == 'SessionState.completed' ||
            state.toString() == 'SessionState.failed') {
          timer.cancel();
          onProgress(1.0);
          return;
        }

        // Try to get statistics
        final statistics = await session.getAllStatistics();
        if (statistics.isNotEmpty) {
          final lastStat = statistics.last;
          final time = lastStat.getTime();
          if (time > 0 && totalMs > 0) {
            final currentMs = time.toDouble();
            final progressValue = (currentMs / totalMs).clamp(0.0, 0.99);
            onProgress(progressValue);
          }
        }
      } catch (e) {
        // Ignore polling errors
      }
    });
  }

  // Wait for completion
  final returnCode = await session.getReturnCode();

  // Stop progress polling
  progressTimer?.cancel();

  // Final progress update
  if (onProgress != null && ReturnCode.isSuccess(returnCode)) {
    onProgress(1.0);
  }

  // Check if successful
  final success = ReturnCode.isSuccess(returnCode);

  // Log failure reason if not successful
  if (!success) {
    final output = await session.getOutput();
    print("FFmpeg conversion failed. Return code: $returnCode");
    print("Output: $output");
  }

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
  return '-i "$input" -c:v libx264 -crf $crf -preset ultrafast -c:a aac "$output" -y';
}

String _buildVideoToAudioCommand(String input, String output, String quality, String format) {
  final bitrate = _getAudioBitrate(quality);
  final codec = _getAudioCodec(format);

  if (codec == 'pcm_s16le') {
    // WAV doesn't use bitrate
    return '-i "$input" -vn -c:a $codec "$output" -y';
  } else if (codec == 'flac') {
    // FLAC uses compression level instead of bitrate
    return '-i "$input" -vn -c:a $codec -compression_level 5 "$output" -y';
  } else {
    return '-i "$input" -vn -c:a $codec -b:a $bitrate "$output" -y';
  }
}

String _buildAudioCommand(String input, String output, String quality, String format) {
  final bitrate = _getAudioBitrate(quality);
  final codec = _getAudioCodec(format);

  if (codec == 'pcm_s16le') {
    return '-i "$input" -c:a $codec "$output" -y';
  } else if (codec == 'flac') {
    return '-i "$input" -c:a $codec -compression_level 5 "$output" -y';
  } else {
    return '-i "$input" -c:a $codec -b:a $bitrate "$output" -y';
  }
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

String _getAudioBitrate(String quality) {
  switch (quality.toLowerCase()) {
    case 'low':
      return '96k';
    case 'medium':
      return '192k';
    case 'high':
      return '320k';
    default:
      return '192k';
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