import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'location_service.dart';

/// Stamps date/time + address (bottom-right) onto a captured photo. Text is
/// drawn white with a dark outline so it stays readable without hiding the
/// image (no background box).
///
/// No company logo is burned in. This app serves both Vehga and Pronto, and a
/// case's company is only known after the vehicle number is looked up — for an
/// offline capture it is never known at all. A logo composited here would be
/// permanent and sometimes wrong, so branding is applied later at the AVO
/// stage, where the case's brand is settled.
class WatermarkService {
  static const double _maxLongSide = 1920;

  /// Watermarks [photoBytes] and writes a JPEG named after
  /// [vehicleNumber]/[photoType] into the app documents folder.
  static Future<File> apply({
    required Uint8List photoBytes,
    required WatermarkLocation location,
    required DateTime timestamp,
    required String vehicleNumber,
    required String photoType,
  }) async {
    // Decode, capping the long side so uploads stay small and fast.
    final rawCodec = await ui.instantiateImageCodec(photoBytes);
    final rawFrame = await rawCodec.getNextFrame();
    final raw = rawFrame.image;

    final longSide =
        raw.width > raw.height ? raw.width.toDouble() : raw.height.toDouble();
    final scale = longSide > _maxLongSide ? _maxLongSide / longSide : 1.0;
    final width = (raw.width * scale).round();
    final height = (raw.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImageRect(
      raw,
      Rect.fromLTWH(0, 0, raw.width.toDouble(), raw.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );

    final pad = width * 0.02;

    _drawStampText(canvas, width, height, pad, location, timestamp);

    final picture = recorder.endRecording();
    final composed = await picture.toImage(width, height);
    final rgba =
        await composed.toByteData(format: ui.ImageByteFormat.rawRgba);

    raw.dispose();
    composed.dispose();

    // JPEG-encode off the UI thread.
    final jpeg = await compute(_encodeJpeg, _EncodeJob(
      width: width,
      height: height,
      rgba: rgba!.buffer.asUint8List(),
    ));

    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(timestamp);
    final file = File(
        '${dir.path}${Platform.pathSeparator}${vehicleNumber}_${photoType}_$stamp.jpg');
    await file.writeAsBytes(jpeg, flush: true);
    return file;
  }

  /// Canonical video width the watermark pieces are rendered against.
  /// FFmpeg scales each piece by its [WatermarkPiece.widthFraction] of the
  /// real frame width, so the result matches the photo watermark at any
  /// resolution or orientation.
  static const double _canonicalWidth = 1080;

  /// Renders the date/time + address block tightly on a transparent canvas
  /// with the standard padding baked in. Overlaying it at the frame's
  /// bottom-right corner reproduces the photo watermark position.
  static Future<WatermarkPiece> buildTextPiece({
    required WatermarkLocation location,
    required DateTime timestamp,
    required String outPath,
  }) async {
    final pad = _canonicalWidth * 0.02;
    final painter =
        _buildStampPainter(_canonicalWidth, location, timestamp);
    final canvasWidth = painter.width + 2 * pad;
    final canvasHeight = painter.height + 2 * pad;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, Offset(pad, pad));

    final file = await _writePicture(
        recorder, canvasWidth.ceil(), canvasHeight.ceil(), outPath);
    return WatermarkPiece(file, canvasWidth / _canonicalWidth);
  }

  static Future<File> _writePicture(
      ui.PictureRecorder recorder, int width, int height, String outPath) async {
    final picture = recorder.endRecording();
    final composed = await picture.toImage(width, height);
    final png = await composed.toByteData(format: ui.ImageByteFormat.png);
    composed.dispose();

    final file = File(outPath);
    await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
    return file;
  }

  static TextPainter _buildStampPainter(
    double width,
    WatermarkLocation location,
    DateTime timestamp,
  ) {
    final dateLine =
        DateFormat('MMM d, yyyy hh:mm:ss a').format(timestamp);
    final baseSize = width * 0.026;

    final shadows = [
      for (final dx in [-1.5, 1.5])
        for (final dy in [-1.5, 1.5])
          Shadow(
              offset: Offset(dx, dy),
              blurRadius: 2,
              color: Colors.black.withValues(alpha: 0.85)),
    ];

    final painter = TextPainter(
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: dateLine,
            style: TextStyle(
              color: Colors.white,
              fontSize: baseSize * 1.15,
              fontWeight: FontWeight.w700,
              height: 1.35,
              shadows: shadows,
            ),
          ),
          TextSpan(
            text: '\n${location.lines.join('\n')}',
            style: TextStyle(
              color: Colors.white,
              fontSize: baseSize,
              fontWeight: FontWeight.w600,
              height: 1.35,
              shadows: shadows,
            ),
          ),
        ],
      ),
    );

    painter.layout(maxWidth: width * 0.75);
    return painter;
  }

  static void _drawStampText(
    Canvas canvas,
    int width,
    int height,
    double pad,
    WatermarkLocation location,
    DateTime timestamp,
  ) {
    final painter =
        _buildStampPainter(width.toDouble(), location, timestamp);
    painter.paint(
        canvas,
        Offset(width - painter.width - pad,
            height - painter.height - pad));
  }

}

/// A pre-rendered watermark element plus how wide it should be relative to
/// the video frame width when overlaid by FFmpeg.
class WatermarkPiece {
  final File file;
  final double widthFraction;
  WatermarkPiece(this.file, this.widthFraction);
}

class _EncodeJob {
  final int width;
  final int height;
  final Uint8List rgba;
  _EncodeJob({required this.width, required this.height, required this.rgba});
}

Uint8List _encodeJpeg(_EncodeJob job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 90);
}
