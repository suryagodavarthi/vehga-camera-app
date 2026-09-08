// Extracts the teal "APP ICON" tile from the brand sheet and produces:
//   assets/app_icon.png     - 1024x1024 full-bleed launcher icon
//   assets/app_icon_fg.png  - adaptive-icon foreground (camera in safe zone)
// Prints the sampled background hex for pubspec's adaptive_icon_background.
//
// Usage: dart run tool/make_icons.dart <path-to-brand-sheet>
import 'dart:io';

import 'package:image/image.dart' as img;

bool _isTeal(img.Pixel p) {
  final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
  return g > 90 && b > 90 && r < g * 0.6 && (g - b).abs() < 45;
}

void main(List<String> args) {
  final src = img.decodeImage(File(args.first).readAsBytesSync())!;
  final w = src.width, h = src.height;

  // The APP ICON tile is the big teal block in the bottom band, right of the
  // teal heading text and left of the LIGHT ICON tile.
  int minX = w, minY = h, maxX = 0, maxY = 0;
  for (var y = (h * 0.70).round(); y < h; y++) {
    for (var x = (w * 0.555).round(); x < (w * 0.76).round(); x++) {
      if (_isTeal(src.getPixel(x, y))) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  final tileW = maxX - minX + 1, tileH = maxY - minY + 1;
  stdout.writeln('tile bbox: x=$minX y=$minY w=$tileW h=$tileH');
  if (tileW < 50 || tileH < 50) {
    stderr.writeln('Tile not found — adjust scan region.');
    exit(1);
  }

  // Inset past the rounded corners so the crop is pure teal to the edges.
  final inset = (tileW * 0.09).round();
  final side = (tileW < tileH ? tileW : tileH) - 2 * inset;
  final crop = img.copyCrop(src,
      x: minX + inset, y: minY + inset, width: side, height: side);

  // Background teal = average of every teal pixel in the crop, which
  // ignores the white camera glyph entirely.
  var rSum = 0, gSum = 0, bSum = 0, n = 0;
  for (final p in crop) {
    if (_isTeal(p)) {
      rSum += p.r.toInt();
      gSum += p.g.toInt();
      bSum += p.b.toInt();
      n++;
    }
  }
  if (n == 0) {
    stderr.writeln('No teal pixels in crop — wrong region.');
    exit(1);
  }
  final sample = img.ColorRgba8(rSum ~/ n, gSum ~/ n, bSum ~/ n, 255);
  final hex = '#'
      '${sample.r.toInt().toRadixString(16).padLeft(2, '0')}'
      '${sample.g.toInt().toRadixString(16).padLeft(2, '0')}'
      '${sample.b.toInt().toRadixString(16).padLeft(2, '0')}';
  stdout.writeln('background hex: $hex (from $n teal px)');

  final base = img.copyResize(crop,
      width: 1024, height: 1024, interpolation: img.Interpolation.cubic);
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(base));

  // Adaptive foreground: full teal canvas with the camera well inside the
  // ~66% safe zone so round/squircle masks never clip it.
  final fg = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(fg,
      color: img.ColorRgba8(
          sample.r.toInt(), sample.g.toInt(), sample.b.toInt(), 255));
  final small = img.copyResize(crop,
      width: 660, height: 660, interpolation: img.Interpolation.cubic);
  img.compositeImage(fg, small, dstX: 182, dstY: 182);
  File('assets/app_icon_fg.png').writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('written assets/app_icon.png and assets/app_icon_fg.png');
}
