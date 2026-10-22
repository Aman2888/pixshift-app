import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A plain RGBA picture (4 bytes per pixel). All pixel maths works on this, so it can run in an isolate.
class Rgba {
  final int w, h;
  final Uint8List d;
  Rgba(this.w, this.h, this.d);
  factory Rgba.blank(int w, int h) => Rgba(w, h, Uint8List(w * h * 4));
  Rgba copy() => Rgba(w, h, Uint8List.fromList(d));
}

class Stroke {
  /// Points as fractions of width and height.
  final List<List<double>> pts;

  /// Brush radius as a fraction of the shorter side.
  final double r;
  Stroke(this.pts, this.r);
}

typedef P = Map<String, dynamic>;

const int kMaxEdge = 12000;
const int kMaxPixels = 64000000;

int c8(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
double num0(P p, String k, double d) => p[k] is num ? (p[k] as num).toDouble() : d;
String str0(P p, String k, String d) => p[k] is String ? p[k] as String : d;
bool bool0(P p, String k, bool d) => p[k] is bool ? p[k] as bool : d;

List<int> hexToRgb(String hex) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (m == null) return [255, 255, 255];
  final n = int.parse(m.group(1)!, radix: 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

ui.Color colorOf(String hex) {
  final c = hexToRgb(hex);
  return ui.Color.fromARGB(255, c[0], c[1], c[2]);
}

String toHexColor(ui.Color c) {
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
  return '#${two(r)}${two(g)}${two(b)}';
}

/* ───────────── ui.Image <-> Rgba ───────────── */

Future<Rgba> toRgba(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  if (bd == null) throw Exception('Could not read the picture.');
  return Rgba(img.width, img.height, bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes).sublist(0));
}

Future<ui.Image> fromRgba(Rgba r) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(r.d, r.w, r.h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<ui.Image> decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final f = await codec.getNextFrame();
  codec.dispose();
  return f.image;
}

/// Draws into a new picture of the given size (like a canvas in the browser).
Future<ui.Image> paint(int w, int h, void Function(ui.Canvas c) f) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  f(c);
  final pic = rec.endRecording();
  final img = pic.toImage(w, h);
  return img;
}

/// Copy of [src] as a new picture.
Future<ui.Image> copyImage(ui.Image src) => paint(src.width, src.height, (c) => c.drawImage(src, ui.Offset.zero, ui.Paint()));

ui.Paint hq([ui.Color? color]) {
  final p = ui.Paint()
    ..isAntiAlias = true
    ..filterQuality = ui.FilterQuality.high;
  if (color != null) p.color = color;
  return p;
}

void drawImageRect(ui.Canvas c, ui.Image img, ui.Rect src, ui.Rect dst, {ui.FilterQuality q = ui.FilterQuality.high}) {
  c.drawImageRect(img, src, dst, ui.Paint()..filterQuality = q..isAntiAlias = true);
}

/// Scales a picture to a new size (used by resize tools).
Future<ui.Image> scaleTo(ui.Image src, int w, int h) =>
    paint(w, h, (c) => drawImageRect(c, src, ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));

/// Puts a picture on a solid background (JPEG has no transparency).
Future<ui.Image> flatten(ui.Image src, [String bg = '#ffffff']) => paint(src.width, src.height, (c) {
      c.drawRect(ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), ui.Paint()..color = colorOf(bg));
      c.drawImage(src, ui.Offset.zero, ui.Paint());
    });

/* ───────────── blur (separable box, 3 passes ≈ Gaussian) ───────────── */

void _boxPass(Uint8List src, Uint8List dst, int w, int h, int r, bool horizontal) {
  final len = horizontal ? w : h;
  final lines = horizontal ? h : w;
  final stepIn = horizontal ? 1 : w;
  final stepLine = horizontal ? w : 1;
  final win = 2 * r + 1;
  int cl(int v) => v < 0 ? 0 : (v > len - 1 ? len - 1 : v);
  for (var l = 0; l < lines; l++) {
    final base = l * stepLine;
    for (var ch = 0; ch < 4; ch++) {
      var sum = 0;
      for (var i = -r; i <= r; i++) {
        sum += src[(base + cl(i) * stepIn) * 4 + ch];
      }
      for (var i = 0; i < len; i++) {
        dst[(base + i * stepIn) * 4 + ch] = (sum + (win >> 1)) ~/ win;
        final add = cl(i + r + 1);
        final sub = cl(i - r);
        sum += src[(base + add * stepIn) * 4 + ch] - src[(base + sub * stepIn) * 4 + ch];
      }
    }
  }
}

/// Returns a blurred copy of the RGBA data. [r] is in pixels.
Uint8List blurData(Uint8List data, int w, int h, num r) {
  final ri = r.round();
  if (ri < 1) return Uint8List.fromList(data);
  var a = Uint8List.fromList(data);
  var b = Uint8List(data.length);
  final rr = math.max(1, (ri / 1.7).round());
  for (var i = 0; i < 3; i++) {
    _boxPass(a, b, w, h, rr, true);
    _boxPass(b, a, w, h, rr, false);
  }
  return a;
}

/* ───────────── mask helpers ───────────── */

/// Paints strokes into a 0/255 mask the size of the picture.
Uint8List strokeMask(List<Stroke> strokes, int w, int h) {
  final out = Uint8List(w * h);
  final base = math.min(w, h);
  void disc(double cx, double cy, double r) {
    final x0 = math.max(0, (cx - r).floor()), x1 = math.min(w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor()), y1 = math.min(h - 1, (cy + r).ceil());
    final r2 = r * r;
    for (var y = y0; y <= y1; y++) {
      final dy = y + 0.5 - cy;
      for (var x = x0; x <= x1; x++) {
        final dx = x + 0.5 - cx;
        if (dx * dx + dy * dy <= r2) out[y * w + x] = 255;
      }
    }
  }

  for (final s in strokes) {
    final r = math.max(1.0, s.r * base);
    if (s.pts.length == 1) {
      disc(s.pts[0][0] * w, s.pts[0][1] * h, r);
      continue;
    }
    for (var i = 1; i < s.pts.length; i++) {
      final ax = s.pts[i - 1][0] * w, ay = s.pts[i - 1][1] * h;
      final bx = s.pts[i][0] * w, by = s.pts[i][1] * h;
      final dist = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      final steps = math.max(1, (dist / math.max(1.0, r * 0.4)).ceil());
      for (var k = 0; k <= steps; k++) {
        final t = k / steps;
        disc(ax + (bx - ax) * t, ay + (by - ay) * t, r);
      }
    }
  }
  return out;
}

List<int>? maskBox(Uint8List m, int w, int h) {
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      if (m[row + x] != 0) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  return x1 < 0 ? null : [x0, y0, x1, y1];
}

/// Grows a mask by r pixels (square window, two fast passes).
Uint8List dilateMask(Uint8List m, int w, int h, int r) {
  if (r < 1) return m;
  Uint8List pass(Uint8List src, bool horizontal) {
    final dst = Uint8List(src.length);
    final len = horizontal ? w : h;
    final lines = horizontal ? h : w;
    final ps = Int32List(len + 1);
    for (var l = 0; l < lines; l++) {
      for (var i = 0; i < len; i++) {
        ps[i + 1] = ps[i] + (src[horizontal ? l * w + i : i * w + l] != 0 ? 1 : 0);
      }
      for (var i = 0; i < len; i++) {
        final a = math.max(0, i - r);
        final b = math.min(len - 1, i + r);
        if (ps[b + 1] - ps[a] > 0) dst[horizontal ? l * w + i : i * w + l] = 255;
      }
    }
    return dst;
  }

  return pass(pass(m, true), false);
}

/// Turns a 0/255 mask into a soft 0..1 mask by blurring it.
Float32List softMask(Uint8List m, int w, int h, num r) {
  final out = Float32List(m.length);
  if (r < 1) {
    for (var i = 0; i < m.length; i++) {
      out[i] = m[i] != 0 ? 1 : 0;
    }
    return out;
  }
  final buf = Uint8List(m.length * 4);
  for (var i = 0; i < m.length; i++) {
    buf[i * 4] = m[i] != 0 ? 255 : 0;
  }
  final bl = blurData(buf, w, h, r);
  for (var i = 0; i < m.length; i++) {
    out[i] = bl[i * 4] / 255;
  }
  return out;
}

/// Largest scale factor that keeps the result inside what the phone can allocate.
double safeFactor(int w, int h, double factor) {
  var f = factor;
  while (f > 1 && (w * f > kMaxEdge || h * f > kMaxEdge || w * f * h * f > kMaxPixels)) {
    f -= 0.5;
  }
  return math.max(1, f);
}

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

int gcd(num a, num b) {
  var x = a.abs().round(), y = b.abs().round();
  while (y != 0) {
    final t = x % y;
    x = y;
    y = t;
  }
  return x == 0 ? 1 : x;
}

String baseName(String name) => name.replaceFirst(RegExp(r'\.[^.]+$'), '');
