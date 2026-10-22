// Decoding, encoding and the "resize / compress / convert" pipeline (port of lib/image.ts).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
// import 'package:flutter_svg/flutter_svg.dart';
// import 'package:flutter_svg/flutter_svg.dart' as svg;
// import 'package:vector_graphics/vector_graphics.dart' as vg;
import 'package:image/image.dart' as im;
import 'package:flutter_svg/flutter_svg.dart' as flutter_svg_pkg;
// import 'package:vector_graphics/vector_graphics.dart' as vector_graphics;
import 'px.dart';

enum Fmt { jpeg, png, webp, avif }

const Map<Fmt, String> kExt = {
  Fmt.jpeg: 'jpg',
  Fmt.png: 'png',
  Fmt.webp: 'webp',
  Fmt.avif: 'avif'
};
const Map<Fmt, String> kMime = {
  Fmt.jpeg: 'image/jpeg',
  Fmt.png: 'image/png',
  Fmt.webp: 'image/webp',
  Fmt.avif: 'image/avif'
};

Fmt? fmtFromString(String s) {
  switch (s) {
    case 'jpeg':
      return Fmt.jpeg;
    case 'png':
      return Fmt.png;
    case 'webp':
      return Fmt.webp;
    case 'avif':
      return Fmt.avif;
  }
  return null;
}

Fmt formatFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png') || n.endsWith('.gif') || n.endsWith('.svg'))
    return Fmt.png;
  if (n.endsWith('.webp')) return Fmt.webp;
  if (n.endsWith('.avif')) return Fmt.avif;
  return Fmt.jpeg;
}

bool isSvgName(String name) => name.toLowerCase().endsWith('.svg');

/// Opens an image file. SVGs have no fixed pixel size, so they are drawn at a useful size.
Future<ui.Image> loadImage(Uint8List bytes, String name,
    {int svgWidth = 1024}) async {
  if (isSvgName(name)) {
    final svgContent = String.fromCharCodes(bytes);

    final info = await flutter_svg_pkg.vg.loadPicture(
      flutter_svg_pkg.SvgStringLoader(svgContent),
      null,
    );

    double w = info.size.width;
    double h = info.size.height;

    if (w <= 0 || h <= 0) {
      w = svgWidth.toDouble();
      h = svgWidth * 0.75;
    }

    final scale = w < 600 ? 1024 / w : 1.0;

    final int ow = math.max<int>(1, (w * scale).round());
    final int oh = math.max<int>(1, (h * scale).round());
    final img = await paint(ow, oh, (c) {
      c.scale(ow / w, oh / h);
      c.drawPicture(info.picture);
    });
    info.picture.dispose();
    return img;
  }
  return decodeBytes(bytes);
}

/// Lossless PNG bytes of a picture.
Future<Uint8List> pngBytes(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) throw Exception('Could not encode the picture.');
  return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
}

Uint8List _quantizedPng(Rgba r, int colours) {
  final image = im.Image.fromBytes(
      width: r.w,
      height: r.h,
      bytes: r.d.buffer,
      numChannels: 4,
      order: im.ChannelOrder.rgba);
  final q = im.quantize(image, numberOfColors: colours);
  return Uint8List.fromList(im.encodePng(q));
}

/// Encodes a picture. [quality] is 1-100. JPEG is flattened on [background] first.
Future<Uint8List> encodeImage(ui.Image img, Fmt fmt, int quality,
    {String background = '#ffffff'}) async {
  switch (fmt) {
    case Fmt.png:
      if (quality >= 100) return pngBytes(img);
      final r = await toRgba(img);
      // Map quality 1-99 onto 16-256 colours.
      final colours =
          math.max(16, math.min(256, (16 + (quality / 99) * 240).round()));
      return compute(_pngJob, [r.w, r.h, r.d, colours]);
    case Fmt.jpeg:
      final flat = await flatten(img, background);
      final src = await pngBytes(flat);
      return FlutterImageCompress.compressWithList(src,
          minWidth: img.width,
          minHeight: img.height,
          quality: quality.clamp(1, 100),
          format: CompressFormat.jpeg,
          keepExif: false,
          autoCorrectionAngle: false);
    case Fmt.webp:
      final src = await pngBytes(img);
      return FlutterImageCompress.compressWithList(src,
          minWidth: img.width,
          minHeight: img.height,
          quality: quality.clamp(1, 100),
          format: CompressFormat.webp,
          keepExif: false,
          autoCorrectionAngle: false);
    case Fmt.avif:
      try {
        final src = await pngBytes(img);
        final qz = ((100 - quality.clamp(1, 100)) * 63 / 100).round();
        return await encodeAvif(src,
            minQuantizer: math.max(0, qz - 8),
            maxQuantizer: math.min(63, qz + 8));
      } catch (_) {
        throw Exception(
            'This phone could not create an AVIF file. Try the WebP tools instead.');
      }
  }
}

Uint8List _pngJob(List<dynamic> a) => _quantizedPng(
    Rgba(a[0] as int, a[1] as int, a[2] as Uint8List), a[3] as int);

class ProcessResult {
  final Uint8List bytes;
  final int width, height;
  ProcessResult(this.bytes, this.width, this.height);
}

enum FitMode { fill, fit, stretch }

/// Draws the picture at the target size and encodes it.
Future<ProcessResult> processImage(ui.Image src,
    {required Fmt format,
    required int quality,
    int? width,
    int? height,
    FitMode fit = FitMode.stretch,
    String background = '#ffffff'}) async {
  final tw = math.max(1, (width ?? src.width).round());
  final th = math.max(1, (height ?? src.height).round());
  final out = await paint(tw, th, (c) {
    if (format == Fmt.jpeg || fit == FitMode.fit) {
      c.drawRect(ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
          ui.Paint()..color = colorOf(background));
    }
    final srcRect =
        ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    if (fit == FitMode.stretch) {
      drawImageRect(c, src, srcRect,
          ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()));
    } else {
      final scale = fit == FitMode.fill
          ? math.max(tw / src.width, th / src.height)
          : math.min(tw / src.width, th / src.height);
      final dw = src.width * scale, dh = src.height * scale;
      drawImageRect(c, src, srcRect,
          ui.Rect.fromLTWH((tw - dw) / 2, (th - dh) / 2, dw, dh));
    }
  });
  final bytes = await encodeImage(out, format, quality, background: background);
  return ProcessResult(bytes, tw, th);
}

class FitResult extends ProcessResult {
  final int quality;
  final bool scaled;
  FitResult(super.bytes, super.w, super.h, this.quality, this.scaled);
}

/// Finds a JPEG/WebP that stays under [maxBytes]; shrinks the picture a little when the quality would look poor.
Future<FitResult> fitUnder(ui.Image src, int maxBytes,
    {Fmt format = Fmt.jpeg, String background = '#ffffff'}) async {
  const good = 50;
  var scale = 1.0;
  FitResult? found;
  for (var round = 0; round < 30; round++) {
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    Future<ProcessResult> enc(int q) => processImage(src,
        format: format,
        quality: q,
        width: w,
        height: h,
        background: background);
    final floor = await enc(5);
    if (floor.bytes.length <= maxBytes) {
      var best = floor;
      var bestQ = 5;
      var lo = 6, hi = 95;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final r = await enc(mid);
        if (r.bytes.length <= maxBytes) {
          best = r;
          bestQ = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      found = FitResult(best.bytes, best.width, best.height, bestQ, scale < 1);
      if (bestQ >= good) return found;
    }
    if (w <= 16 && h <= 16) break;
    scale *= 0.85;
  }
  if (found != null) return found;
  throw Exception(
      'Could not reach that size. Try a simpler or smaller picture.');
}
