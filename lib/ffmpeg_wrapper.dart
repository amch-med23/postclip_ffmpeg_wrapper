import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';

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
      // Use FFmpegKit.cancel() with the session ID to abort.
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

  // Use Completer to handle async result
  final completer = Completer<bool>();

  // Use executeAsync to get live progress updates via the StatisticsCallback
  FFmpegKit.executeAsync(
    cmd,
        (session) async {
      // This is the session complete callback
      controller?._session = session;
      final returnCode = await session.getReturnCode();
      final success = ReturnCode.isSuccess(returnCode);

      // Final progress update
      if (onProgress != null) {
        onProgress(success ? 1.0 : 0.0);
      }

      // Log failure reason if not successful
      if (!success) {
        final output = await session.getOutput();
        print("FFmpeg conversion failed. Return code: $returnCode");
        print("Output: $output");
      }

      // Complete the future with the success status
      completer.complete(success);
    },
        (log) {
      // Log callback - you can add logging here if needed
    },
        (statistics) {
      // This is the statistics callback for live progress
      if (onProgress != null && totalDuration != null) {
        final totalMs = totalDuration.inMilliseconds.toDouble();
        final currentMs = statistics.getTime();

        if (currentMs > 0 && totalMs > 0) {
          final progressValue = (currentMs / totalMs).clamp(0.0, 1.0);
          onProgress(progressValue);
        }
      }
    },
  );

  return completer.future;
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

/// Clips media from a start time to an end time, then exports it with chosen settings.
/// The duration is calculated as end - start.
Future<bool> clipMedia({
  required String inputPath,
  required String outputPath,
  required double startTimeSeconds,
  required double endTimeSeconds,
  required String quality,
  required String format, // Added format explicitly for output
  Function(double)? onProgress,
  FFmpegConversionController? controller,
}) async {
  final lowerFormat = format.toLowerCase();
  final isAudioFormat = ['mp3', 'wav', 'aac', 'flac'].contains(lowerFormat);
  final isVideoFormat = ['mp4', 'mov'].contains(lowerFormat);
  final durationSeconds = endTimeSeconds - startTimeSeconds;

  if (durationSeconds <= 0) {
    throw ArgumentError("Clip duration must be greater than zero.");
  }
  if (!isAudioFormat && !isVideoFormat) {
    throw UnsupportedError("Unsupported format: $format");
  }

  // Determine if the input file is a video or just audio
  final inputIsVideo = _isVideoFile(inputPath);

  late String cmd;

  // The output format should always be the target format (e.g., mp4 or mp3)
  final targetFormat = isVideoFormat ? lowerFormat : lowerFormat;

  if (inputIsVideo) {
    // Video-to-Video or Video-to-Audio Clipping
    cmd = _buildVideoClipCommand(
      inputPath,
      outputPath,
      startTimeSeconds,
      durationSeconds,
      quality,
      targetFormat,
    );
  } else if (isAudioFormat) {
    // Audio-to-Audio Clipping
    cmd = _buildAudioClipCommand(
      inputPath,
      outputPath,
      startTimeSeconds,
      durationSeconds,
      quality,
      targetFormat,
    );
  } else {
    throw UnsupportedError("Unsupported conversion from this type to $format");
  }


  // --- Logic for execution, duration, and progress calculation remains the same ---

  // Get duration for progress calculation (Note: FFprobe on input for duration is correct)
  Duration? totalDuration;
  try {
    // NOTE: For progress to be accurate, we should ideally use the *clip duration* // calculated here, not the full file duration.
    // However, the progress handler in the wrapper uses the full media duration.
    // We will keep using the full duration check in the existing wrapper
    // but the actual progress bar should rely on the FFmpeg statistics
    // *relative to the clip length*.

    // For simplicity with the existing wrapper's progress logic, we use the CLIP duration:
    totalDuration = Duration(milliseconds: (durationSeconds * 1000).round());
  } catch (e) {
    print("Could not determine media duration: $e");
  }

  // Use Completer to handle async result
  final completer = Completer<bool>();

  // Execute Async (using the existing logic from convertMedia)
  FFmpegKit.executeAsync(
    cmd,
        (session) async {
      // Session complete callback (same as convertMedia)
      controller?._session = session;
      final returnCode = await session.getReturnCode();
      final success = ReturnCode.isSuccess(returnCode);

      if (onProgress != null) {
        onProgress(success ? 1.0 : 0.0);
      }

      if (!success) {
        final output = await session.getOutput();
        print("FFmpeg clip failed. Return code: $returnCode");
        print("Output: $output");
      }

      completer.complete(success);
    },
        (log) {
      // Log callback
    },
        (statistics) {
      // Statistics callback for live progress
      // Progress calculation MUST use the clip duration
      if (onProgress != null && totalDuration != null) {
        final clipTotalMs = totalDuration.inMilliseconds.toDouble();
        final currentMs = statistics.getTime(); // time elapsed in the clip process

        if (currentMs > 0 && clipTotalMs > 0) {
          final progressValue = (currentMs / clipTotalMs).clamp(0.0, 1.0);
          onProgress(progressValue);
        }
      }
    },
  );

  return completer.future;
}

// --- NEW HELPER COMMANDS ---

// The key to effective trimming:
// - '-ss' (seek) BEFORE '-i' is faster but less accurate.
// - '-ss' AFTER '-i' is slower but frame-accurate (used here).
// - '-t' is the duration (end-start).

String _buildVideoClipCommand(
    String input,
    String output,
    double start,
    double duration,
    String quality,
    String format,
    ) {
  final crf = _getCRF(quality);
  // '-ss' after input for accurate seek; '-t' for duration
  if (format == 'mp4' || format == 'mov') {
    return '-i "$input" -ss $start -t $duration -c:v libx264 -crf $crf -preset ultrafast -c:a aac "$output" -y';
  } else {
    // If clipping video to audio (e.g., MP3)
    final bitrate = _getAudioBitrate(quality);
    final codec = _getAudioCodec(format);
    return '-i "$input" -ss $start -t $duration -vn -c:a $codec -b:a $bitrate "$output" -y';
  }
}

String _buildAudioClipCommand(
    String input,
    String output,
    double start,
    double duration,
    String quality,
    String format,
    ) {
  final bitrate = _getAudioBitrate(quality);
  final codec = _getAudioCodec(format);

  // '-ss' after input for accurate seek; '-t' for duration
  if (codec == 'pcm_s16le') {
    // WAV
    return '-i "$input" -ss $start -t $duration -c:a $codec "$output" -y';
  } else if (codec == 'flac') {
    // FLAC
    return '-i "$input" -ss $start -t $duration -c:a $codec -compression_level 5 "$output" -y';
  } else {
    // MP3/AAC
    return '-i "$input" -ss $start -t $duration -c:a $codec -b:a $bitrate "$output" -y';
  }
}