import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'location_service.dart';
import 'watermark_service.dart';

/// Burns the same watermark used on photos (date/time + address, bottom-right)
/// into a recorded video. Like the photo watermark, it carries no company logo
/// — see [WatermarkService] for why.
///
/// The text block is pre-rendered as a small transparent PNG and FFmpeg
/// scales/positions it with main_w/main_h expressions against the decoded
/// frame, so the placement is correct for any resolution and any rotation the
/// phone recorded with — no rotation probing needed.
class VideoWatermarkService {
  /// Watermarks [input] and returns the stamped MP4 named after
  /// [vehicleNumber]. [onProgress] reports 0.0–1.0 encode progress.
  static Future<File> apply({
    required File input,
    required WatermarkLocation location,
    required DateTime timestamp,
    required String vehicleNumber,
    void Function(double fraction)? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final stampName = DateFormat('yyyyMMdd_HHmmss').format(timestamp);

    final textPiece = await WatermarkService.buildTextPiece(
      location: location,
      timestamp: timestamp,
      outPath: '${dir.path}${sep}wm_text_$stampName.png',
    );

    final durationMs = await _probeDurationMs(input.path);

    final output =
        File('${dir.path}$sep${vehicleNumber}_VehicleVideo_$stampName.mp4');

    final textFrac = textPiece.widthFraction.toStringAsFixed(4);

    // Pad the frame up to 4:3 first (bars, never cropping), then overlay the
    // watermark pieces. Pieces carry their own padding margins, so they sit
    // flush against the corners of the padded 4:3 frame.
    const padTo43 = "pad=w='trunc(max(iw,ih*4/3)/2)*2'"
        ":h='trunc(max(ih,iw*3/4)/2)*2':x=(ow-iw)/2:y=(oh-ih)/2";

    final inputs = [input.path, textPiece.file.path];
    final filter = '[0:v]$padTo43[p0];'
        '[1:v][p0]scale2ref=w=main_w*$textFrac:h=-1[tx][v0];'
        '[v0][tx]overlay=main_w-overlay_w:main_h-overlay_h';

    final command = '-y ${inputs.map((p) => '-i "$p"').join(' ')} '
        '-filter_complex "$filter" '
        '-c:v libx264 -preset veryfast -crf 27 -pix_fmt yuv420p '
        '-c:a copy -movflags +faststart "${output.path}"';

    final completer = Completer<void>();
    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          completer.complete();
        } else {
          final logs = await session.getAllLogsAsString();
          final tail = (logs == null || logs.length < 600)
              ? logs
              : logs.substring(logs.length - 600);
          completer.completeError(
              Exception('Video watermarking failed.\n$tail'));
        }
      },
      null,
      (statistics) {
        final done = statistics.getTime();
        if (durationMs > 0 && done > 0) {
          onProgress?.call((done / durationMs).clamp(0.0, 1.0));
        }
      },
    );
    try {
      await completer.future;
    } finally {
      try {
        await textPiece.file.delete();
      } catch (_) {}
    }

    return output;
  }

  /// Duration is only used for the progress indicator, so failures are soft.
  static Future<int> _probeDurationMs(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final duration = session.getMediaInformation()?.getDuration();
      return ((double.tryParse(duration ?? '') ?? 0) * 1000).round();
    } catch (_) {
      return 0;
    }
  }
}
