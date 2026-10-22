// Pixel operations (pure Dart, run inside isolates). Direct ports of lib/ops.ts from the website.
import 'dart:math' as math;
import 'dart:typed_data';
import 'px.dart';

typedef RGB = List<double>;

Rgba unsharp(Rgba s, double amount, num radius) {
  final d = s.d;
  final bl = blurData(d, s.w, s.h, radius);
  for (var i = 0; i < d.length; i += 4) {
    d[i] = c8(d[i] + amount * (d[i] - bl[i]));
    d[i + 1] = c8(d[i + 1] + amount * (d[i + 1] - bl[i + 1]));
    d[i + 2] = c8(d[i + 2] + amount * (d[i + 2] - bl[i + 2]));
  }
  return s;
}

List<int> _autoLevels(Uint8List d) {
  final hist = Int32List(256);
  final n = d.length ~/ 4;
  for (var i = 0; i < d.length; i += 4) {
    hist[(0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]).round()]++;
  }
  final clip = n * 0.005;
  var lo = 0, hi = 255, acc = 0;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc > clip) {
      lo = i;
      break;
    }
  }
  acc = 0;
  for (var i = 255; i >= 0; i--) {
    acc += hist[i];
    if (acc > clip) {
      hi = i;
      break;
    }
  }
  if (hi - lo < 16) return [0, 255];
  return [lo, hi];
}

Rgba enhance(Rgba s, P p) {
  final d = s.d;
  final lh = bool0(p, 'auto', true) ? _autoLevels(d) : [0, 255];
  final lo = lh[0], hi = lh[1];
  final gain = 255 / (hi - lo);
  final bright = num0(p, 'brightness', 0) * 1.5;
  final ct = num0(p, 'contrast', 0) * 2;
  final cf = (259 * (ct + 255)) / (255 * (259 - ct));
  final sat = 1 + num0(p, 'saturation', 0) / 100;
  final warm = num0(p, 'warmth', 0) * 0.35;
  for (var i = 0; i < d.length; i += 4) {
    var r = (d[i] - lo) * gain + bright;
    var g = (d[i + 1] - lo) * gain + bright;
    var b = (d[i + 2] - lo) * gain + bright;
    r = cf * (r - 128) + 128;
    g = cf * (g - 128) + 128;
    b = cf * (b - 128) + 128;
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    r = l + (r - l) * sat + warm;
    g = l + (g - l) * sat;
    b = l + (b - l) * sat - warm;
    d[i] = c8(r);
    d[i + 1] = c8(g);
    d[i + 2] = c8(b);
  }
  return s;
}

Rgba sharpen(Rgba s, P p) {
  final scale = math.max(1.0, math.min(s.w, s.h) / 900);
  return unsharp(s, num0(p, 'amount', 1), math.max(1, (num0(p, 'radius', 2) * scale).round()));
}

Rgba bw(Rgba s, P p) {
  final d = s.d;
  final ct = num0(p, 'contrast', 0) * 2;
  final cf = (259 * (ct + 255)) / (255 * (259 - ct));
  final thr = bool0(p, 'threshold', false);
  final t = num0(p, 'level', 128);
  for (var i = 0; i < d.length; i += 4) {
    var l = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
    l = cf * (l - 128) + 128;
    if (thr) l = l >= t ? 255 : 0;
    final v = c8(l);
    d[i] = d[i + 1] = d[i + 2] = v;
  }
  return s;
}

Rgba blurBg(Rgba s, P p) {
  final w = s.w, h = s.h, d = s.d;
  final radius = num0(p, 'blur', 0.02) * math.min(w, h);
  final bl = blurData(d, w, h, radius);
  final cx = num0(p, 'cx', 0.5) * w;
  final cy = num0(p, 'cy', 0.5) * h;
  final rx = math.max(1.0, num0(p, 'size', 0.5) * w * 0.5);
  final ry = math.max(1.0, num0(p, 'size', 0.5) * h * 0.5);
  final feather = math.max(0.01, num0(p, 'feather', 0.4));
  for (var yy = 0; yy < h; yy++) {
    for (var xx = 0; xx < w; xx++) {
      final dist = math.sqrt(math.pow((xx - cx) / rx, 2) + math.pow((yy - cy) / ry, 2));
      var t = (dist - 1) / feather;
      t = t < 0 ? 0 : (t > 1 ? 1 : t * t * (3 - 2 * t));
      if (t == 0) continue;
      final i = (yy * w + xx) * 4;
      d[i] = c8(d[i] + (bl[i] - d[i]) * t);
      d[i + 1] = c8(d[i + 1] + (bl[i + 1] - d[i + 1]) * t);
      d[i + 2] = c8(d[i + 2] + (bl[i + 2] - d[i + 2]) * t);
    }
  }
  return s;
}

/* ───────────── remove object (inpainting) ───────────── */

class _Level {
  final int w, h;
  final Float32List col;
  final Uint8List known;
  final Int32List unk;
  _Level(this.w, this.h, this.col, this.known, this.unk);
}

_Level _makeLevel(int w, int h, Float32List col, Uint8List known) {
  var n = 0;
  for (var i = 0; i < known.length; i++) {
    if (known[i] == 0) n++;
  }
  final unk = Int32List(n);
  var k = 0;
  for (var i = 0; i < known.length; i++) {
    if (known[i] == 0) unk[k++] = i;
  }
  return _Level(w, h, col, known, unk);
}

Float32List? _harmonicFill(Uint8List d, Uint8List m, int w, int h) {
  final col0 = Float32List(w * h * 3);
  final known0 = Uint8List(w * h);
  var anyKnown = false;
  for (var i = 0; i < w * h; i++) {
    col0[i * 3] = d[i * 4].toDouble();
    col0[i * 3 + 1] = d[i * 4 + 1].toDouble();
    col0[i * 3 + 2] = d[i * 4 + 2].toDouble();
    if (m[i] == 0) {
      known0[i] = 1;
      anyKnown = true;
    }
  }
  if (!anyKnown) return null;
  final levels = <_Level>[_makeLevel(w, h, col0, known0)];
  while (levels.last.unk.isNotEmpty) {
    final L = levels.last;
    final nw = math.max(1, (L.w / 2).ceil());
    final nh = math.max(1, (L.h / 2).ceil());
    final col = Float32List(nw * nh * 3);
    final wt = Float32List(nw * nh);
    for (var y = 0; y < L.h; y++) {
      for (var x = 0; x < L.w; x++) {
        final i = y * L.w + x;
        if (L.known[i] == 0) continue;
        final j = (y >> 1) * nw + (x >> 1);
        col[j * 3] += L.col[i * 3];
        col[j * 3 + 1] += L.col[i * 3 + 1];
        col[j * 3 + 2] += L.col[i * 3 + 2];
        wt[j]++;
      }
    }
    final known = Uint8List(nw * nh);
    for (var j = 0; j < wt.length; j++) {
      if (wt[j] > 0) {
        col[j * 3] /= wt[j];
        col[j * 3 + 1] /= wt[j];
        col[j * 3 + 2] /= wt[j];
        known[j] = 1;
      }
    }
    levels.add(_makeLevel(nw, nh, col, known));
    if (nw == 1 && nh == 1) break;
  }
  final top = levels.last;
  if (top.unk.isNotEmpty) return null;
  for (var l = levels.length - 2; l >= 0; l--) {
    final L = levels[l];
    final Pp = levels[l + 1];
    for (var k = 0; k < L.unk.length; k++) {
      final i = L.unk[k];
      final x = i % L.w;
      final y = (i - x) ~/ L.w;
      final fx = math.min(Pp.w - 1.0, math.max(0.0, (x + 0.5) / 2 - 0.5));
      final fy = math.min(Pp.h - 1.0, math.max(0.0, (y + 0.5) / 2 - 0.5));
      final x0 = fx.floor(), y0 = fy.floor();
      final x1 = math.min(Pp.w - 1, x0 + 1), y1 = math.min(Pp.h - 1, y0 + 1);
      final ax = fx - x0, ay = fy - y0;
      for (var c = 0; c < 3; c++) {
        final t2 = Pp.col[(y0 * Pp.w + x0) * 3 + c] * (1 - ax) + Pp.col[(y0 * Pp.w + x1) * 3 + c] * ax;
        final bot = Pp.col[(y1 * Pp.w + x0) * 3 + c] * (1 - ax) + Pp.col[(y1 * Pp.w + x1) * 3 + c] * ax;
        L.col[i * 3 + c] = t2 * (1 - ay) + bot * ay;
      }
    }
    final iters = l == 0 ? 10 : 14;
    for (var it = 0; it < iters; it++) {
      final fwd = it % 2 == 0;
      for (var k = 0; k < L.unk.length; k++) {
        final i = L.unk[fwd ? k : L.unk.length - 1 - k];
        final x = i % L.w;
        final y = (i - x) ~/ L.w;
        double r = 0, g = 0, b = 0;
        var n = 0;
        if (x > 0) {
          final j = (i - 1) * 3;
          r += L.col[j];
          g += L.col[j + 1];
          b += L.col[j + 2];
          n++;
        }
        if (x < L.w - 1) {
          final j = (i + 1) * 3;
          r += L.col[j];
          g += L.col[j + 1];
          b += L.col[j + 2];
          n++;
        }
        if (y > 0) {
          final j = (i - L.w) * 3;
          r += L.col[j];
          g += L.col[j + 1];
          b += L.col[j + 2];
          n++;
        }
        if (y < L.h - 1) {
          final j = (i + L.w) * 3;
          r += L.col[j];
          g += L.col[j + 1];
          b += L.col[j + 2];
          n++;
        }
        L.col[i * 3] = r / n;
        L.col[i * 3 + 1] = g / n;
        L.col[i * 3 + 2] = b / n;
      }
    }
  }
  return levels[0].col;
}

Rgba inpaint(Rgba s, List<Stroke> strokes) {
  if (strokes.isEmpty) return s;
  final w = s.w, h = s.h;
  final full = strokeMask(strokes, w, h);
  final box = maskBox(full, w, h);
  if (box == null) return s;
  final grow = math.max(2, (math.min(w, h) * 0.004).round());
  final bw0 = box[2] - box[0] + 1;
  final bh0 = box[3] - box[1] + 1;
  final margin = math.min(500, math.max(40, (math.max(bw0, bh0) * 0.6).round())) + grow + 4;
  final cx0 = math.max(0, box[0] - margin);
  final cy0 = math.max(0, box[1] - margin);
  final cx1 = math.min(w - 1, box[2] + margin);
  final cy1 = math.min(h - 1, box[3] + margin);
  final cw = cx1 - cx0 + 1;
  final ch = cy1 - cy0 + 1;
  final d = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    final so = ((y + cy0) * w + cx0) * 4;
    d.setRange(y * cw * 4, (y + 1) * cw * 4, s.d, so);
  }
  var m = Uint8List(cw * ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      m[y * cw + x] = full[(y + cy0) * w + x + cx0];
    }
  }
  m = dilateMask(m, cw, ch, grow);
  final filled = _harmonicFill(d, m, cw, ch);
  if (filled == null) return s;

  final smooth = blurData(d, cw, ch, 2);
  final knownIdx = <int>[];
  for (var i = 0; i < m.length; i++) {
    if (m[i] == 0) knownIdx.add(i);
  }
  var seed = 987654321;
  double rnd() {
    seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    return seed / 4294967296;
  }

  final out = Uint8List(d.length);
  for (var i = 0; i < m.length; i++) {
    final k = i * 4;
    if (m[i] != 0) {
      final j = knownIdx[(rnd() * knownIdx.length).floor()] * 4;
      for (var c = 0; c < 3; c++) {
        final hp = math.max(-18, math.min(18, d[j + c] - smooth[j + c]));
        out[k + c] = c8(filled[i * 3 + c] + hp * 0.9);
      }
      out[k + 3] = 255;
    } else {
      out[k] = d[k];
      out[k + 1] = d[k + 1];
      out[k + 2] = d[k + 2];
      out[k + 3] = d[k + 3];
    }
  }
  final a = softMask(m, cw, ch, math.max(1.0, grow * 0.8));
  for (var i = 0; i < m.length; i++) {
    if (a[i] <= 0) continue;
    final k = i * 4;
    final t = m[i] != 0 ? math.max(a[i], 0.999) : a[i];
    d[k] = c8(d[k] * (1 - t) + out[k] * t);
    d[k + 1] = c8(d[k + 1] * (1 - t) + out[k + 1] * t);
    d[k + 2] = c8(d[k + 2] * (1 - t) + out[k + 2] * t);
    d[k + 3] = 255;
  }
  for (var y = 0; y < ch; y++) {
    final so = ((y + cy0) * w + cx0) * 4;
    s.d.setRange(so, so + cw * 4, d, y * cw * 4);
  }
  return s;
}

/* ───────────── blur / pixelate / cover part of a picture ───────────── */

Rgba redact(Rgba s, P p, List<Stroke> strokes) {
  if (strokes.isEmpty) return s;
  final w = s.w, h = s.h;
  final full = strokeMask(strokes, w, h);
  final box = maskBox(full, w, h);
  if (box == null) return s;
  final style = str0(p, 'style', 'pixelate');
  final strength = num0(p, 'strength', 0.03);
  final base = math.min(w, h);
  final blurR = math.max(4.0, strength * 3 * base);
  final block = math.max(4, (strength * 1.6 * base).round());
  int cx0, cy0, cx1, cy1;
  if (style == 'pixelate') {
    cx0 = (box[0] ~/ block) * block;
    cy0 = (box[1] ~/ block) * block;
    cx1 = math.min(w, (((box[2] + 1) / block).ceil()) * block) - 1;
    cy1 = math.min(h, (((box[3] + 1) / block).ceil()) * block) - 1;
  } else {
    final mg = (blurR * 2).ceil() + 2;
    cx0 = math.max(0, box[0] - mg);
    cy0 = math.max(0, box[1] - mg);
    cx1 = math.min(w - 1, box[2] + mg);
    cy1 = math.min(h - 1, box[3] + mg);
  }
  final cw = cx1 - cx0 + 1;
  final ch = cy1 - cy0 + 1;
  final d = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    final so = ((y + cy0) * w + cx0) * 4;
    d.setRange(y * cw * 4, (y + 1) * cw * 4, s.d, so);
  }
  final m = Uint8List(cw * ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      m[y * cw + x] = full[(y + cy0) * w + x + cx0];
    }
  }
  Uint8List eff;
  if (style == 'blur') {
    eff = blurData(d, cw, ch, blurR);
  } else if (style == 'cover') {
    eff = Uint8List(d.length);
    for (var i = 0; i < eff.length; i += 4) {
      eff[i + 3] = 255;
    }
  } else {
    eff = Uint8List(d.length);
    for (var by = 0; by < ch; by += block) {
      for (var bx = 0; bx < cw; bx += block) {
        var r = 0, g = 0, b = 0, n = 0;
        final ye = math.min(ch, by + block);
        final xe = math.min(cw, bx + block);
        for (var yy = by; yy < ye; yy++) {
          for (var xx = bx; xx < xe; xx++) {
            final k = (yy * cw + xx) * 4;
            r += d[k];
            g += d[k + 1];
            b += d[k + 2];
            n++;
          }
        }
        for (var yy = by; yy < ye; yy++) {
          for (var xx = bx; xx < xe; xx++) {
            final k = (yy * cw + xx) * 4;
            eff[k] = c8(r / n);
            eff[k + 1] = c8(g / n);
            eff[k + 2] = c8(b / n);
            eff[k + 3] = 255;
          }
        }
      }
    }
  }
  final a = style == 'blur' ? softMask(m, cw, ch, math.max(1.0, base * 0.004)) : null;
  for (var i = 0; i < m.length; i++) {
    final double t = a != null ? (m[i] != 0 ? math.max(a[i], 0.999) : a[i].toDouble()) : (m[i] != 0 ? 1.0 : 0.0);
    if (t <= 0) continue;
    final k = i * 4;
    d[k] = c8(d[k] * (1 - t) + eff[k] * t);
    d[k + 1] = c8(d[k + 1] * (1 - t) + eff[k + 1] * t);
    d[k + 2] = c8(d[k + 2] * (1 - t) + eff[k + 2] * t);
  }
  for (var y = 0; y < ch; y++) {
    final so = ((y + cy0) * w + cx0) * 4;
    s.d.setRange(so, so + cw * 4, d, y * cw * 4);
  }
  return s;
}

/* ───────────── background remover / changer / transparent colour ───────────── */

List<RGB> _edgeColors(Uint8List d, int w, int h, [int max = 4]) {
  final buckets = <int, List<double>>{}; // key -> [n, r, g, b]
  var total = 0;
  void add(int x, int y) {
    final i = (y * w + x) * 4;
    final key = ((d[i] >> 4) << 8) | ((d[i + 1] >> 4) << 4) | (d[i + 2] >> 4);
    final e = buckets.putIfAbsent(key, () => [0, 0, 0, 0]);
    e[0]++;
    e[1] += d[i];
    e[2] += d[i + 1];
    e[3] += d[i + 2];
    total++;
  }

  for (var x = 0; x < w; x++) {
    add(x, 0);
    add(x, h - 1);
  }
  for (var y = 1; y < h - 1; y++) {
    add(0, y);
    add(w - 1, y);
  }
  final list = buckets.values.toList()..sort((a, b) => b[0].compareTo(a[0]));
  final out = <RGB>[];
  for (final e in list) {
    if (out.length >= max) break;
    if (out.isNotEmpty && e[0] < total * 0.06) break;
    final col = <double>[e[1] / e[0], e[2] / e[0], e[3] / e[0]];
    final near = out.any((o) => math.sqrt(math.pow(o[0] - col[0], 2) + math.pow(o[1] - col[1], 2) + math.pow(o[2] - col[2], 2)) < 36);
    if (near) continue;
    out.add(col);
  }
  return out.isNotEmpty ? out : [<double>[255, 255, 255]];
}

double _dist(Uint8List d, int i, List<num> c) {
  final a = d[i] - c[0], b = d[i + 1] - c[1], e = d[i + 2] - c[2];
  return math.sqrt(a * a + b * b + e * e);
}

Rgba bgRemove(Rgba s, P p, [String? fill]) {
  final w = s.w, h = s.h, d = s.d;
  final sm = blurData(d, w, h, 1);
  final refs = _edgeColors(sm, w, h, 4);
  final tol = num0(p, 'tolerance', 30);
  final thr = tol * 2.2;
  final drift = thr * 2;
  final step = 5 + tol * 0.15;
  double nearest(int i) {
    var best = double.infinity;
    for (final r in refs) {
      final v = _dist(sm, i, r);
      if (v < best) best = v;
    }
    return best;
  }

  var bg = Uint8List(w * h);
  final stack = <int>[];
  void seed(int px, int py) {
    final idx = py * w + px;
    if (bg[idx] == 0 && nearest(idx * 4) <= thr) {
      bg[idx] = 255;
      stack.add(idx);
    }
  }

  for (var xx = 0; xx < w; xx++) {
    seed(xx, 0);
    seed(xx, h - 1);
  }
  for (var yy = 0; yy < h; yy++) {
    seed(0, yy);
    seed(w - 1, yy);
  }
  double stepDiff(int a, int b) {
    final x1 = sm[a] - sm[b], y1 = sm[a + 1] - sm[b + 1], z1 = sm[a + 2] - sm[b + 2];
    return math.sqrt(x1 * x1 + y1 * y1 + z1 * z1);
  }

  void tryAdd(int from, int to) {
    if (bg[to] != 0) return;
    final dn = nearest(to * 4);
    if (dn <= thr || (dn <= drift && stepDiff(to * 4, from * 4) <= step)) {
      bg[to] = 255;
      stack.add(to);
    }
  }

  while (stack.isNotEmpty) {
    final idx = stack.removeLast();
    final px = idx % w;
    final py = (idx - px) ~/ w;
    if (px > 0) tryAdd(idx, idx - 1);
    if (px < w - 1) tryAdd(idx, idx + 1);
    if (py > 0) tryAdd(idx, idx - w);
    if (py < h - 1) tryAdd(idx, idx + w);
  }

  // Drop leftover specks of foreground.
  final label = Int32List(w * h);
  final sizes = <int>[0];
  var nLabels = 0;
  for (var i = 0; i < label.length; i++) {
    if (bg[i] != 0 || label[i] != 0) continue;
    nLabels++;
    var size = 0;
    final st = <int>[i];
    label[i] = nLabels;
    while (st.isNotEmpty) {
      final j = st.removeLast();
      size++;
      final jx = j % w;
      if (jx > 0 && bg[j - 1] == 0 && label[j - 1] == 0) {
        label[j - 1] = nLabels;
        st.add(j - 1);
      }
      if (jx < w - 1 && bg[j + 1] == 0 && label[j + 1] == 0) {
        label[j + 1] = nLabels;
        st.add(j + 1);
      }
      if (j >= w && bg[j - w] == 0 && label[j - w] == 0) {
        label[j - w] = nLabels;
        st.add(j - w);
      }
      if (j < label.length - w && bg[j + w] == 0 && label[j + w] == 0) {
        label[j + w] = nLabels;
        st.add(j + w);
      }
    }
    sizes.add(size);
  }
  final biggest = sizes.fold<int>(0, math.max);
  for (var i = 0; i < label.length; i++) {
    if (label[i] != 0 && sizes[label[i]] < biggest * 0.04) bg[i] = 255;
  }

  final pull = (math.min(w, h) / 900).round();
  if (pull > 0) bg = dilateMask(bg, w, h, pull);

  final soft = (num0(p, 'softness', 1) * math.max(1.0, math.min(w, h) / 600)).round();
  final t = softMask(bg, w, h, soft);
  final Float32List? smoothed = soft > 0 ? t : null;

  final near = Uint8List(w * h * 4);
  for (var i = 0; i < bg.length; i++) {
    if (bg[i] != 0) {
      near[i * 4] = d[i * 4];
      near[i * 4 + 1] = d[i * 4 + 1];
      near[i * 4 + 2] = d[i * 4 + 2];
      near[i * 4 + 3] = 255;
    }
  }
  final nb = blurData(near, w, h, math.max(3, soft * 2 + 3));
  final fillRgb = fill != null ? hexToRgb(fill) : null;
  for (var i = 0; i < bg.length; i++) {
    final double tt = smoothed != null ? smoothed[i].toDouble() : (bg[i] != 0 ? 1.0 : 0.0);
    final k = i * 4;
    if (tt <= 0) continue;
    if (tt < 0.995 && nb[k + 3] > 8) {
      final bw_ = nb[k + 3] / 255;
      final bR = nb[k] / bw_, bG = nb[k + 1] / bw_, bB = nb[k + 2] / bw_;
      final keep = math.max(0.05, 1 - tt);
      d[k] = c8((d[k] - bR * tt) / keep);
      d[k + 1] = c8((d[k + 1] - bG * tt) / keep);
      d[k + 2] = c8((d[k + 2] - bB * tt) / keep);
    }
    if (fillRgb != null) {
      d[k] = c8(d[k] * (1 - tt) + fillRgb[0] * tt);
      d[k + 1] = c8(d[k + 1] * (1 - tt) + fillRgb[1] * tt);
      d[k + 2] = c8(d[k + 2] * (1 - tt) + fillRgb[2] * tt);
      d[k + 3] = 255;
    } else {
      d[k + 3] = tt >= 0.995 ? 0 : (d[k + 3] * (1 - tt)).round();
    }
  }
  return s;
}

Rgba transparentColor(Rgba s, P p) {
  final w = s.w, h = s.h, d = s.d;
  final sm = blurData(d, w, h, math.max(2, (math.min(w, h) / 400).round()));
  final px = math.min(w - 1, math.max(0, (num0(p, 'px', 0) * (w - 1)).round()));
  final py = math.min(h - 1, math.max(0, (num0(p, 'py', 0) * (h - 1)).round()));
  final hasPick = bool0(p, 'hasPick', false);
  late List<double> ref;
  if (!hasPick) {
    ref = _edgeColors(sm, w, h, 1)[0];
  } else {
    double r = 0, g = 0, b = 0;
    var n = 0;
    for (var yy = math.max(0, py - 2); yy <= math.min(h - 1, py + 2); yy++) {
      for (var xx = math.max(0, px - 2); xx <= math.min(w - 1, px + 2); xx++) {
        final k = (yy * w + xx) * 4;
        r += sm[k];
        g += sm[k + 1];
        b += sm[k + 2];
        n++;
      }
    }
    ref = [r / n, g / n, b / n];
  }
  final thr = math.max(1.0, num0(p, 'tolerance', 30) * 2.2);
  final lo = thr * 0.7;

  Uint8List? allowed;
  if (bool0(p, 'contiguous', false)) {
    final reg = Uint8List(w * h);
    final st = <int>[];
    void go(int i) {
      if (reg[i] == 0 && _dist(sm, i * 4, ref) <= thr) {
        reg[i] = 255;
        st.add(i);
      }
    }

    if (!hasPick) {
      for (var xx = 0; xx < w; xx++) {
        go(xx);
        go((h - 1) * w + xx);
      }
      for (var yy = 0; yy < h; yy++) {
        go(yy * w);
        go(yy * w + w - 1);
      }
    } else {
      go(py * w + px);
    }
    while (st.isNotEmpty) {
      final i = st.removeLast();
      final ix = i % w;
      if (ix > 0) go(i - 1);
      if (ix < w - 1) go(i + 1);
      if (i >= w) go(i - w);
      if (i < reg.length - w) go(i + w);
    }
    allowed = dilateMask(reg, w, h, 1);
  }

  for (var i = 0; i < w * h; i++) {
    if (allowed != null && allowed[i] == 0) continue;
    final dd = _dist(sm, i * 4, ref);
    if (dd >= thr) continue;
    final t = dd <= lo ? 1.0 : (thr - dd) / (thr - lo);
    final k = i * 4;
    if (t < 0.995) {
      final keep = math.max(0.05, 1 - t);
      d[k] = c8((d[k] - ref[0] * t) / keep);
      d[k + 1] = c8((d[k + 1] - ref[1] * t) / keep);
      d[k + 2] = c8((d[k + 2] - ref[2] * t) / keep);
      d[k + 3] = (d[k + 3] * (1 - t)).round();
    } else {
      d[k + 3] = 0;
    }
  }
  return s;
}

/* ───────────── filters, invert, blur, sketch, posterize ───────────── */

RGB _sepia(double r, double g, double b) => [r * 0.393 + g * 0.769 + b * 0.189, r * 0.349 + g * 0.686 + b * 0.168, r * 0.272 + g * 0.534 + b * 0.131];

final Map<String, RGB Function(double, double, double)> _filters = {
  'sepia': _sepia,
  'vintage': (r, g, b) {
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    final a = [l * 0.35 + r * 0.65 + 18, l * 0.3 + g * 0.7 + 8, l * 0.4 + b * 0.6 - 6];
    return a.map((v) => 0.82 * v + 22).toList();
  },
  'cool': (r, g, b) => [r * 0.9, g * 1.0, b * 1.15 + 8],
  'warm': (r, g, b) => [r * 1.12 + 6, g * 1.03, b * 0.88],
  'vivid': (r, g, b) {
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    final a = [l + (r - l) * 1.45, l + (g - l) * 1.45, l + (b - l) * 1.45];
    return a.map((v) => (v - 128) * 1.08 + 128).toList();
  },
  'fade': (r, g, b) => [r * 0.8 + 40, g * 0.8 + 40, b * 0.8 + 44],
  'noir': (r, g, b) {
    final l = (0.299 * r + 0.587 * g + 0.114 * b - 128) * 1.3 + 128;
    return [l, l, l];
  },
  'cyan': (r, g, b) {
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    return [l * 0.55 + r * 0.45 - 10, l * 0.9 + g * 0.1 + 10, l * 0.9 + b * 0.1 + 24];
  },
};

const List<List<String>> kFilterNames = [
  ['sepia', 'Sepia'], ['vintage', 'Vintage'], ['warm', 'Warm'], ['cool', 'Cool'],
  ['vivid', 'Vivid'], ['fade', 'Faded'], ['noir', 'Noir'], ['cyan', 'Teal'],
];

Rgba filterOp(Rgba s, P p) {
  final d = s.d;
  final fn = _filters[str0(p, 'preset', 'sepia')] ?? _sepia;
  final a = num0(p, 'strength', 1).clamp(0.0, 1.0);
  for (var i = 0; i < d.length; i += 4) {
    final o = fn(d[i].toDouble(), d[i + 1].toDouble(), d[i + 2].toDouble());
    d[i] = c8(d[i] + (o[0] - d[i]) * a);
    d[i + 1] = c8(d[i + 1] + (o[1] - d[i + 1]) * a);
    d[i + 2] = c8(d[i + 2] + (o[2] - d[i + 2]) * a);
  }
  return s;
}

Rgba invertOp(Rgba s, P p) {
  final d = s.d;
  final a = num0(p, 'strength', 1).clamp(0.0, 1.0);
  for (var i = 0; i < d.length; i += 4) {
    d[i] = c8(d[i] + (255 - 2 * d[i]) * a);
    d[i + 1] = c8(d[i + 1] + (255 - 2 * d[i + 1]) * a);
    d[i + 2] = c8(d[i + 2] + (255 - 2 * d[i + 2]) * a);
  }
  return s;
}

Rgba blurAll(Rgba s, P p) {
  final r = math.max(0.0, num0(p, 'amount', 0.02) * math.min(s.w, s.h));
  return Rgba(s.w, s.h, blurData(s.d, s.w, s.h, r));
}

Rgba sketch(Rgba s, P p) {
  final w = s.w, h = s.h, d = s.d;
  final gray = Uint8List(d.length);
  for (var i = 0; i < d.length; i += 4) {
    final l = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
    final v = c8(255 - l);
    gray[i] = gray[i + 1] = gray[i + 2] = v;
    gray[i + 3] = 255;
  }
  final bl = blurData(gray, w, h, math.max(1.0, num0(p, 'detail', 0.02) * math.min(w, h)));
  final mix = num0(p, 'darkness', 1).clamp(0.3, 2.0);
  for (var i = 0; i < d.length; i += 4) {
    final base = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
    var v = bl[i] >= 255 ? 255.0 : math.min(255.0, (base * 255) / (255 - bl[i]));
    v = 255 - (255 - v) * mix;
    final o = c8(v);
    d[i] = d[i + 1] = d[i + 2] = o;
    d[i + 3] = 255;
  }
  return s;
}

Rgba posterize(Rgba s, int levels) {
  if (levels < 2) return s;
  final step = 255 / (levels - 1);
  final d = s.d;
  for (var i = 0; i < d.length; i += 4) {
    for (var k = 0; k < 3; k++) {
      d[i + k] = c8((d[i + k] / step).round() * step);
    }
  }
  return s;
}

/// Entry point used with Isolate.run. [op] is one of the pixel-only operations.
Rgba runPixelOp(String op, Rgba src, P p, List<Stroke> strokes, [String? fill]) {
  final s = src.copy();
  switch (op) {
    case 'enhance':
      return enhance(s, p);
    case 'sharpen':
      return sharpen(s, p);
    case 'bw':
      return bw(s, p);
    case 'blurbg':
      return blurBg(s, p);
    case 'inpaint':
      return inpaint(s, strokes);
    case 'redact':
      return redact(s, p, strokes);
    case 'bgremove':
      return bgRemove(s, p);
    case 'bgchange':
      return bgRemove(s, p, str0(p, 'fill', '#ffffff'));
    case 'transparent':
      return transparentColor(s, p);
    case 'filter':
      return filterOp(s, p);
    case 'invert':
      return invertOp(s, p);
    case 'blur':
      return blurAll(s, p);
    case 'sketch':
      return sketch(s, p);
    case 'unsharp':
      return unsharp(s, num0(p, 'amount', 0.6), num0(p, 'radius', 1));
    case 'posterize':
      return posterize(s, num0(p, 'levels', 0).round());
  }
  return s;
}
