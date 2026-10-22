// Colour helpers and median-cut palette (port of lib/colors.ts).
import 'dart:math' as math;
import 'dart:typed_data';

typedef Rgb = List<double>;

String toHex(Rgb c) => '#${c.map((v) => v.round().clamp(0, 255).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

List<int> toHsl(Rgb c) {
  final r = c[0] / 255, g = c[1] / 255, b = c[2] / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  double h = 0, s = 0;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    h = mx == r ? (g - b) / d + (g < b ? 6 : 0) : (mx == g ? (b - r) / d + 2 : (r - g) / d + 4);
    h *= 60;
  }
  return [h.round(), (s * 100).round(), (l * 100).round()];
}

/// True when dark ink reads better on this colour.
bool darkInkOn(Rgb c) => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] > 150;

class Swatch {
  final Rgb rgb;
  final double share;
  Swatch(this.rgb, this.share);
}

class _E {
  Rgb rgb;
  int n;
  _E(this.rgb, this.n);
}

/// Median-cut palette. [data] is RGBA pixels (already small). Most common colour first.
List<Swatch> palette(Uint8List data, int n) {
  final map = <int, List<double>>{};
  var total = 0;
  for (var i = 0; i < data.length; i += 4) {
    if (data[i + 3] <= 128) continue;
    final key = ((data[i] >> 3) << 10) | ((data[i + 1] >> 3) << 5) | (data[i + 2] >> 3);
    final e = map.putIfAbsent(key, () => [0, 0, 0, 0]);
    e[0]++;
    e[1] += data[i];
    e[2] += data[i + 1];
    e[3] += data[i + 2];
    total++;
  }
  if (total == 0) return [];
  final entries = <_E>[];
  for (final e in map.values) {
    entries.add(_E([e[1] / e[0], e[2] / e[0], e[3] / e[0]], e[0].toInt()));
  }
  var boxes = <List<_E>>[entries];
  while (boxes.length < n) {
    var bi = -1;
    var best = 0.0;
    var chBest = 0;
    for (var i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      if (b.length < 2) continue;
      for (var c = 0; c < 3; c++) {
        double lo = 255, hi = 0;
        var w = 0;
        for (final e in b) {
          lo = math.min(lo, e.rgb[c]);
          hi = math.max(hi, e.rgb[c]);
          w += e.n;
        }
        final score = (hi - lo) * math.sqrt(w.toDouble());
        if (score > best) {
          best = score;
          bi = i;
          chBest = c;
        }
      }
    }
    if (bi < 0) break;
    final b = boxes[bi]..sort((x, y) => x.rgb[chBest].compareTo(y.rgb[chBest]));
    final half = b.fold<int>(0, (t, e) => t + e.n) / 2;
    var acc = 0;
    var cut = 1;
    for (var i = 0; i < b.length - 1; i++) {
      acc += b[i].n;
      cut = i + 1;
      if (acc >= half) break;
    }
    boxes = [...boxes.sublist(0, bi), b.sublist(0, cut), b.sublist(cut), ...boxes.sublist(bi + 1)];
  }
  final out = <Swatch>[];
  for (final b in boxes) {
    var w = 0;
    double r = 0, g = 0, bl = 0;
    for (final e in b) {
      w += e.n;
      r += e.rgb[0] * e.n;
      g += e.rgb[1] * e.n;
      bl += e.rgb[2] * e.n;
    }
    if (w == 0) continue;
    out.add(Swatch([r / w, g / w, bl / w], w / total));
  }
  out.sort((a, b) => b.share.compareTo(a.share));
  return out;
}
