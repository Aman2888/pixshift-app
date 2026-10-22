// Canvas-style operations (dart:ui) plus the dispatcher that runs any editor operation.
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart' as pt;
import 'ops_pixel.dart';
import 'px.dart';

/// Runs a pixel-only operation in a background isolate.
Future<ui.Image> _viaPixels(ui.Image src, String op, P p, List<Stroke> strokes) async {
  final r = await toRgba(src);
  final out = await Isolate.run(() => runPixelOp(op, r, p, strokes));
  return fromRgba(out);
}

/// Draws text with an optional outline. [x],[y] is the anchor; y is the vertical centre of the line.
void drawText(ui.Canvas c, String text, double size, ui.Color fill, double x, double y,
    {String align = 'left', ui.Color? outline, double outlineW = 0, String family = 'sans', double alpha = 1, double? maxWidth, bool heavy = true}) {
  pt.TextStyle mk(ui.Paint? fg, ui.Paint? stroke) => pt.TextStyle(
        fontSize: size,
        fontWeight: heavy ? ui.FontWeight.w800 : ui.FontWeight.w400,
        fontFamily: family == 'serif' ? 'serif' : family == 'mono' ? 'monospace' : family == 'impact' ? 'sans-serif-condensed' : null,
        foreground: fg ?? stroke,
        height: 1.0,
      );
  final fillPaint = ui.Paint()..color = fill.withValues(alpha: fill.a * alpha);
  final tpFill = pt.TextPainter(text: pt.TextSpan(text: text, style: mk(fillPaint, null)), textDirection: ui.TextDirection.ltr);
  tpFill.layout(maxWidth: maxWidth ?? double.infinity);
  final w = tpFill.width, h = tpFill.height;
  double left = x;
  if (align == 'center') left = x - w / 2;
  if (align == 'right') left = x - w;
  final off = ui.Offset(left, y - h / 2);
  if (outline != null && outlineW > 0) {
    final sp = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = outlineW
      ..strokeJoin = ui.StrokeJoin.round
      ..color = outline.withValues(alpha: outline.a * alpha);
    final tpS = pt.TextPainter(text: pt.TextSpan(text: text, style: mk(null, sp)), textDirection: ui.TextDirection.ltr);
    tpS.layout(maxWidth: maxWidth ?? double.infinity);
    tpS.paint(c, off);
  }
  tpFill.paint(c, off);
}

double measureText(String text, double size, {String family = 'sans', bool heavy = true}) {
  final tp = pt.TextPainter(
    text: pt.TextSpan(
      text: text,
      style: pt.TextStyle(
        fontSize: size,
        fontWeight: heavy ? ui.FontWeight.w800 : ui.FontWeight.w400,
        fontFamily: family == 'serif' ? 'serif' : family == 'mono' ? 'monospace' : family == 'impact' ? 'sans-serif-condensed' : null,
        height: 1.0,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  return tp.width;
}

/* ───────────── operations ───────────── */

Future<ui.Image> rotateOp(ui.Image src, P p) async {
  final quarter = ((num0(p, 'quarter', 0).round() % 4) + 4) % 4;
  final flipH = bool0(p, 'flipH', false);
  final flipV = bool0(p, 'flipV', false);
  final angle = num0(p, 'angle', 0) * math.pi / 180;
  final bg = str0(p, 'bg', 'transparent');
  final sw = src.width.toDouble(), sh = src.height.toDouble();

  final swap = quarter % 2 == 1;
  final aw = (swap ? src.height : src.width), ah = (swap ? src.width : src.height);
  final a = await paint(aw, ah, (c) {
    c.translate(aw / 2, ah / 2);
    c.rotate(quarter * math.pi / 2);
    c.scale(flipH ? -1 : 1, flipV ? -1 : 1);
    c.drawImage(src, ui.Offset(-sw / 2, -sh / 2), hq());
  });
  if (angle == 0) return a;

  final cs = math.cos(angle).abs(), sn = math.sin(angle).abs();
  final w = (aw * cs + ah * sn).ceil();
  final h = (aw * sn + ah * cs).ceil();
  return paint(w, h, (c) {
    if (bg != 'transparent') c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = colorOf(bg));
    c.translate(w / 2, h / 2);
    c.rotate(angle);
    c.drawImage(a, ui.Offset(-aw / 2, -ah / 2), hq());
  });
}

Future<ui.Image> watermarkOp(ui.Image src, P p) async {
  final text = str0(p, 'text', '').trim();
  if (text.isEmpty) return copyImage(src);
  final w = src.width, h = src.height;
  final base = math.min(w, h).toDouble();
  final size = math.max(8.0, num0(p, 'size', 0.06) * base);
  final pos = str0(p, 'pos', 'br');
  final colorHex = str0(p, 'color', '#ffffff');
  final color = colorOf(colorHex);
  final alpha = num0(p, 'opacity', 0.5).clamp(0.0, 1.0);
  final outline = colorHex.toLowerCase() == '#ffffff' ? const ui.Color.fromRGBO(0, 0, 0, 0.45) : const ui.Color.fromRGBO(255, 255, 255, 0.45);
  final lw = math.max(1.0, size / 14);
  final tw = measureText(text, size);
  return paint(w, h, (c) {
    c.drawImage(src, ui.Offset.zero, ui.Paint());
    if (pos == 'tile') {
      final ang = num0(p, 'angle', -30) * math.pi / 180;
      final gapX = tw + size * 2;
      final gapY = size * 3;
      c.save();
      c.translate(w / 2, h / 2);
      c.rotate(ang);
      final reach = math.sqrt((w * w + h * h).toDouble());
      var row = 0;
      for (var yy = -reach; yy < reach; yy += gapY, row++) {
        for (var xx = -reach + (row % 2 == 1 ? gapX / 2 : 0); xx < reach; xx += gapX) {
          drawText(c, text, size, color, xx, yy, outline: outline, outlineW: lw, alpha: alpha);
        }
      }
      c.restore();
    } else {
      final m = size * 0.6;
      final col = pos.length > 1 ? pos[1] : 'r';
      final row = pos.isNotEmpty ? pos[0] : 'b';
      final align = col == 'l' ? 'left' : col == 'c' ? 'center' : 'right';
      final px = col == 'l' ? m : col == 'c' ? w / 2 : w - m;
      final py = row == 't' ? m + size / 2 : row == 'm' ? h / 2 : h - m - size / 2;
      drawText(c, text, size, color, px, py, align: align, outline: outline, outlineW: lw, alpha: alpha);
    }
  });
}

Future<ui.Image> upscaleOp(ui.Image src, P p) async {
  final target = safeFactor(src.width, src.height, num0(p, 'factor', 2));
  var cur = await copyImage(src);
  var done = 1.0;
  while (done < target - 0.001) {
    final step = math.min(2.0, target / done);
    final nw = math.max(1, (cur.width * step).round()), nh = math.max(1, (cur.height * step).round());
    final from = cur;
    cur = await paint(nw, nh, (c) => drawImageRect(c, from, ui.Rect.fromLTWH(0, 0, from.width.toDouble(), from.height.toDouble()), ui.Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble())));
    done *= step;
  }
  if (target > 1) {
    final r = await toRgba(cur);
    final radius = math.max(1, (target / 2).round());
    final amount = num0(p, 'sharp', 0.6);
    final out = await Isolate.run(() => runPixelOp('unsharp', r, {'amount': amount, 'radius': radius}, const []));
    return fromRgba(out);
  }
  return cur;
}

Future<ui.Image> borderOp(ui.Image src, P p) async {
  final base = math.min(src.width, src.height);
  final bwid = (num0(p, 'width', 0.03) * base).round();
  final W = src.width + bwid * 2, H = src.height + bwid * 2;
  final radius = num0(p, 'radius', 0) * math.min(W, H);
  return paint(W, H, (c) {
    double rr(double r, double w, double h) => math.max(0.0, math.min(r, math.min(w / 2, h / 2)));
    if (bwid > 0) {
      c.drawRRect(ui.RRect.fromRectXY(ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()), rr(radius, W.toDouble(), H.toDouble()), rr(radius, W.toDouble(), H.toDouble())),
          ui.Paint()..color = colorOf(str0(p, 'color', '#ffffff'))..isAntiAlias = true);
    }
    c.save();
    final ir = rr(math.max(0.0, radius - bwid), src.width.toDouble(), src.height.toDouble());
    c.clipRRect(ui.RRect.fromRectXY(ui.Rect.fromLTWH(bwid.toDouble(), bwid.toDouble(), src.width.toDouble(), src.height.toDouble()), ir, ir), doAntiAlias: true);
    c.drawImage(src, ui.Offset(bwid.toDouble(), bwid.toDouble()), ui.Paint());
    c.restore();
  });
}

Future<ui.Image> pixelArtOp(ui.Image src, P p) async {
  final w = src.width, h = src.height;
  final b = math.max(2, (num0(p, 'size', 0.02) * math.min(w, h)).round());
  final sw = math.max(1, (w / b).round()), sh = math.max(1, (h / b).round());
  var small = await paint(sw, sh, (c) => drawImageRect(c, src, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble())));
  final levels = num0(p, 'levels', 0).round();
  if (levels >= 2) {
    final r = await toRgba(small);
    small = await fromRgba(posterize(r, levels));
  }
  final s2 = small;
  return paint(w, h, (c) => drawImageRect(c, s2, ui.Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()), ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), q: ui.FilterQuality.none));
}

Future<ui.Image> vignetteOp(ui.Image src, P p) async {
  final w = src.width, h = src.height;
  final strength = num0(p, 'strength', 0.6).clamp(0.0, 1.0);
  final size = num0(p, 'size', 0.55).clamp(0.1, 1.0);
  final rad = math.sqrt((w * w + h * h).toDouble()) / 2;
  final light = str0(p, 'tone', 'dark') == 'light';
  final rgb = light ? [255, 255, 255] : [0, 0, 0];
  final clear = ui.Color.fromARGB(0, rgb[0], rgb[1], rgb[2]);
  final full = ui.Color.fromARGB((strength * 255).round(), rgb[0], rgb[1], rgb[2]);
  return paint(w, h, (c) {
    c.drawImage(src, ui.Offset.zero, ui.Paint());
    final shader = ui.Gradient.radial(ui.Offset(w / 2, h / 2), rad, [clear, clear, full], [0, size * 0.6, 1]);
    c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..shader = shader);
  });
}

Future<ui.Image> addTextOp(ui.Image src, P p) async {
  final lines = str0(p, 'text', '').split('\n').map((l) => l.trimRight()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return copyImage(src);
  final w = src.width, h = src.height;
  final base = math.min(w, h).toDouble();
  final size = math.max(8.0, num0(p, 'size', 0.08) * base);
  final family = str0(p, 'font', 'sans');
  final heavy = family != 'impact' ? true : true;
  final pos = str0(p, 'pos', 'bc');
  final col = pos.length > 1 ? pos[1] : 'c';
  final row = pos.isNotEmpty ? pos[0] : 'b';
  final align = col == 'l' ? 'left' : col == 'r' ? 'right' : 'center';
  final m = size * 0.7;
  final lh = size * 1.18;
  final total = lh * lines.length;
  final px = col == 'l' ? m : col == 'r' ? w - m : w / 2;
  final top = row == 't' ? m : row == 'm' ? (h - total) / 2 : h - m - total;
  final colorHex = str0(p, 'color', '#ffffff');
  final color = colorOf(colorHex);
  final bar = bool0(p, 'bar', false);
  final outline = bool0(p, 'outline', true);
  return paint(w, h, (c) {
    c.drawImage(src, ui.Offset.zero, ui.Paint());
    if (bar) {
      final widest = lines.map((l) => measureText(l, size, family: family, heavy: heavy)).reduce(math.max);
      final bx = col == 'l' ? px - size * 0.4 : col == 'r' ? px - widest - size * 0.4 : px - widest / 2 - size * 0.4;
      final rect = ui.Rect.fromLTWH(bx, top - size * 0.2, widest + size * 0.8, total + size * 0.4);
      c.drawRRect(ui.RRect.fromRectXY(rect, size * 0.25, size * 0.25), ui.Paint()..color = const ui.Color.fromRGBO(0, 0, 0, 0.55));
    }
    for (var i = 0; i < lines.length; i++) {
      final py = top + lh * i + lh / 2;
      drawText(c, lines[i], size, color, px, py,
          align: align,
          family: family,
          heavy: heavy,
          outline: (outline && !bar) ? (colorHex.toLowerCase() == '#000000' ? const ui.Color.fromRGBO(255, 255, 255, 0.8) : const ui.Color.fromRGBO(0, 0, 0, 0.75)) : null,
          outlineW: math.max(2.0, size / 7));
    }
  });
}

List<double> parseRatio(String r) {
  final m = RegExp(r'^(\d+(?:\.\d+)?):(\d+(?:\.\d+)?)$').firstMatch(r);
  return m != null ? [double.parse(m.group(1)!), double.parse(m.group(2)!)] : [1, 1];
}

Future<ui.Image> padOp(ui.Image src, P p) async {
  final rr = parseRatio(str0(p, 'ratio', '1:1'));
  final target = rr[0] / rr[1];
  final cur = src.width / src.height;
  var W = src.width, H = src.height;
  if (cur > target) {
    H = (src.width / target).round();
  } else {
    W = (src.height * target).round();
  }
  final extra = math.max(0.0, num0(p, 'margin', 0));
  W = (W * (1 + extra)).round();
  H = (H * (1 + extra)).round();
  final fill = str0(p, 'fill', 'color');
  ui.Image? blurred;
  if (fill == 'blur') {
    final s = math.max(W / src.width, H / src.height);
    final sw = math.max(8, (W / 8).round()), sh = math.max(8, (H / 8).round());
    final small = await paint(sw, sh, (c) {
      final dw = src.width * s / 8, dh = src.height * s / 8;
      drawImageRect(c, src, ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), ui.Rect.fromLTWH((sw - dw) / 2, (sh - dh) / 2, dw, dh));
    });
    final r = await toRgba(small);
    final bl = blurData(r.d, r.w, r.h, math.max(2.0, math.min(r.w, r.h) * 0.06));
    blurred = await fromRgba(Rgba(r.w, r.h, bl));
  }
  final bl2 = blurred;
  return paint(W, H, (c) {
    if (bl2 != null) {
      drawImageRect(c, bl2, ui.Rect.fromLTWH(0, 0, bl2.width.toDouble(), bl2.height.toDouble()), ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
    } else if (fill != 'transparent') {
      c.drawRect(ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()), ui.Paint()..color = colorOf(str0(p, 'color', '#ffffff')));
    }
    c.drawImage(src, ui.Offset(((W - src.width) / 2).roundToDouble(), ((H - src.height) / 2).roundToDouble()), hq());
  });
}

/// Runs one editor operation. Always returns a new picture.
Future<ui.Image> render(String op, ui.Image src, P p, [List<Stroke> strokes = const []]) {
  switch (op) {
    case 'rotate':
      return rotateOp(src, p);
    case 'watermark':
      return watermarkOp(src, p);
    case 'exif':
      return copyImage(src);
    case 'upscale':
      return upscaleOp(src, p);
    case 'border':
      return borderOp(src, p);
    case 'pixel':
      return pixelArtOp(src, p);
    case 'vignette':
      return vignetteOp(src, p);
    case 'text':
      return addTextOp(src, p);
    case 'pad':
      return padOp(src, p);
    default:
      return _viaPixels(src, op, p, strokes);
  }
}

/// True when the result can have transparent pixels, so PNG (or WebP) must be used.
bool needsAlpha(String op, P p) {
  if (op == 'bgremove' || op == 'transparent') return true;
  if (op == 'border') return num0(p, 'radius', 0) > 0;
  if (op == 'pad') return str0(p, 'fill', 'color') == 'transparent';
  if (op == 'rotate') return num0(p, 'angle', 0) != 0 && str0(p, 'bg', 'transparent') == 'transparent';
  return false;
}
