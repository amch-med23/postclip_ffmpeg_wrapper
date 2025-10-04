import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:ffmpeg_kit_flutter_new/session_complete_callback.dart';
import 'package:ffmpeg_kit_flutter_new/statistics_callback.dart';
import 'package:ffmpeg_kit_flutter_new/log_callback.dart';


/// A controller to manage FFmpeg conversion (pause not supported natively)
class FFmpegConversionController {
  Session? _session;
  bool get isRunning => _session != null;

  /// Aborts any ongoing conversion
  Future<void> abort() async {
    final session = _session;
    if (session != null) {
      await session.cancel();
      _session = null;
    }
  }
}

/// Converts media to: MP4, MOV, MP3, WAV, AAC, FLAC.
/// Supports: video-to-video, audio-to-audio, and video-to-audio.
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
  final inputIsAudio = !inputIsVideo;

  late String cmd;

  if (inputIsAudio && isAudioFormat) {
    cmd = _buildAudioCommand(inputPath, outputPath, quality, lowerFormat);
  } else if (inputIsVideo && isAudioFormat) {
    cmd = _buildVideoToAudioCommand(inputPath, outputPath, quality, lowerFormat);
  } else if (inputIsVideo && isVideoFormat) {
    cmd = _buildVideoCommand(inputPath, outputPath, quality);
  } else {
    throw UnsupportedError("Unsupported conversion from this type to $format");
  }

  Duration? totalDuration;
  Completer<bool> completer = Completer<bool>();

  // First, extract duration (for progress tracking)
  await FFmpegKit.executeAsync(
    '-i "$inputPath"',
    logCallback: (log) {
      final msg = log.getMessage();
      if (msg.contains("Duration:")) {
        final regex = RegExp(r'Duration: (\d+):(\d+):(\d+).(\d+)');
        final match = regex.firstMatch(msg);
        if (match != null) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final s = int.parse(match.group(3)!);
          totalDuration = Duration(hours: h, minutes: m, seconds: s);
        }
      }
    },
  );

  // Now run the real conversion
  final session = await FFmpegKit.executeAsync(
    cmd,
    statisticsCallback: StatisticsCallback((Statistics stats) {
      // progress logic
      if (totalDuration != null && onProgress != null) {
        final time = Duration(milliseconds: stats.getTime());
        final ratio = time.inMilliseconds / totalDuration!.inMilliseconds;
        onProgress(ratio.clamp(0.0, 1.0));
      }
    }),
    completeCallback: SessionCompleteCallback((session) async {
      final rc = await session.getReturnCode();
      final success = rc?.isValueSuccess() ?? false;
      completer.complete(success);
    }),
    logCallback: LogCallback((log) {
      // log parsing logic
      final rc = await session.getReturnCode();
      final success = rc?.isValueSuccess() ?? false;
      completer.complete(success);
    }),
  );


  // Keep reference for abort
  controller?._session = session;

  return completer.future;
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

String _getAudioCodec(String format) { // we need to support more formats in here as allowed by the ffmpeg library
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
