// Photo collage and story collage. Port of components/CollageTool.tsx.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/files.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

const _maxPics = 12;
const _longEdge = 2000;
const _shapes = {'1:1': [1, 1], '4:5': [4, 5], '9:16': [9, 16], '16:9': [16, 9], '3:2': [3, 2]};

List<List<double>> _gridRects(int n, int cols) {
  final rows = (n / cols).ceil();
  final out = <List<double>>[];
  for (var r = 0; r < rows; r++) {
    final inRow = r == rows - 1 ? n - cols * (rows - 1) : cols;
    for (var c = 0; c < inRow; c++) {
      out.add([c / inRow, r / rows, 1 / inRow, 1 / rows]);
    }
  }
  return out;
}

List<List<double>> _layoutRects(String layout, int n, double aspect) {
  if (n == 1) return [[0, 0, 1, 1]];
  switch (layout) {
    case 'cols':
      return List.generate(n, (i) => [i / n, 0, 1 / n, 1]);
    case 'rows':
      return List.generate(n, (i) => [0, i / n, 1, 1 / n]);
    case 'left':
      final rest = n - 1;
      return [[0, 0, 0.62, 1], ...List.generate(rest, (i) => [0.62, i / rest, 0.38, 1 / rest])];
    case 'top':
      final rest = n - 1;
      return [[0, 0, 1, 0.62], ...List.generate(rest, (i) => [i / rest, 0.62, 1 / rest, 0.38])];
  }
  final cols = math.max(1, math.min(n, math.sqrt(n * aspect).round()));
  return _gridRects(n, cols);
}

Future<ui.Image> _paintCollage(int W, int H, List<Pic> items, String layout, double gapF, double padF, double radF, String bg, bool transparent) {
  return paint(W, H, (c) {
    if (!transparent) c.drawRect(ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()), ui.Paint()..color = colorOf(bg));
    final base = math.min(W, H).toDouble();
    final gap = gapF * base, pad = padF * base;
    final ax = pad, ay = pad, aw = W - pad * 2, ah = H - pad * 2;
    final rects = _layoutRects(layout, items.length, W / H);
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      final left = ax + r[0] * aw + (r[0] > 0.0001 ? gap / 2 : 0);
      final top = ay + r[1] * ah + (r[1] > 0.0001 ? gap / 2 : 0);
      final right = ax + (r[0] + r[2]) * aw - (r[0] + r[2] < 0.9999 ? gap / 2 : 0);
      final bottom = ay + (r[1] + r[3]) * ah - (r[1] + r[3] < 0.9999 ? gap / 2 : 0);
      final w = right - left, h = bottom - top;
      if (w < 2 || h < 2) continue;
      final p = items[i];
      final s = math.max(w / p.w, h / p.h);
      final sw = w / s, sh = h / s;
      c.save();
      final rad = math.min(radF * base, math.min(w / 2, h / 2));
      c.clipRRect(ui.RRect.fromRectXY(ui.Rect.fromLTWH(left, top, w, h), rad, rad), doAntiAlias: true);
      drawImageRect(c, p.image, ui.Rect.fromLTWH((p.w - sw) / 2, (p.h - sh) / 2, sw, sh), ui.Rect.fromLTWH(left, top, w, h));
      c.restore();
    }
  });
}

class CollageEngine extends StatefulWidget {
  final Tool tool;
  const CollageEngine({super.key, required this.tool});
  @override
  State<CollageEngine> createState() => _CollageEngineState();
}

class _CollageEngineState extends State<CollageEngine> {
  final List<Pic> pics = [];
  late String layout = widget.tool.mode == 'left' ? 'left' : 'grid';
  late String shape = widget.tool.mode == 'story' ? '9:16' : '1:1';
  double gapPct = 2, padPct = 2, radPct = 0;
  String bg = '#ffffff';
  bool clearBg = false, busy = false;
  Fmt fmt = Fmt.jpeg;
  String error = '', message = '';
  ui.Image? shown;
  Uint8List? out;
  String outName = '';
  int _tok = 0;

  List<Pic> get used => pics.take(_maxPics).toList();
  int get _W {
    final s = _shapes[shape]!;
    return s[0] >= s[1] ? _longEdge : (_longEdge * s[0] / s[1]).round();
  }

  int get _H {
    final s = _shapes[shape]!;
    return s[0] >= s[1] ? (_longEdge * s[1] / s[0]).round() : _longEdge;
  }

  bool get _transparent => clearBg && fmt == Fmt.png;

  Future<void> _preview() async {
    if (used.isEmpty) {
      setState(() => shown = null);
      return;
    }
    final t = ++_tok;
    final k = 720 / math.max(_W, _H);
    final img = await _paintCollage((_W * k).round(), (_H * k).round(), used, layout, gapPct / 100, padPct / 100, radPct / 100, bg, _transparent);
    if (mounted && t == _tok) setState(() => shown = img);
  }

  void _upd(VoidCallback f) {
    setState(() {
      f();
      out = null;
    });
    _preview();
  }

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept);
      _upd(() {
        pics.addAll(got);
        error = pics.length > _maxPics ? 'A collage holds up to $_maxPics pictures. Extra ones are ignored.' : '';
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save() async {
    if (used.isEmpty) return;
    setState(() {
      busy = true;
      out = null;
    });
    try {
      final img = await _paintCollage(_W, _H, used, layout, gapPct / 100, padPct / 100, radPct / 100, bg, _transparent);
      final bytes = await encodeImage(img, fmt, fmt == Fmt.png ? 100 : 92, background: bg);
      setState(() {
        out = bytes;
        outName = 'pixshift-collage.${kExt[fmt]}';
        message = '$_W×$_H · ${formatBytes(bytes.length)}';
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PickZone(icon: widget.tool.icon, name: widget.tool.name, acceptLabel: widget.tool.acceptLabel, count: pics.length, multiple: true, onTap: _pick),
      const SizedBox(height: 12),
      if (error.isNotEmpty) InfoBox(error),
      if (pics.isNotEmpty) ...[
        Text('Pictures, in order', style: body(14, w: FontWeight.w800)),
        const SizedBox(height: 6),
        PicStrip(
          pics: pics,
          onRemove: (p) => _upd(() => pics.remove(p)),
          onMove: (i, d) => _upd(() {
            final p = pics.removeAt(i);
            pics.insert(i + d, p);
          }),
        ),
        const SizedBox(height: 12),
        if (shown != null) Panel(padding: const EdgeInsets.all(8), child: Checker(child: Center(child: UiImageView(shown!, maxHeight: 420)))),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Seg<String>(label: 'Layout', value: layout, options: const [('grid', 'Grid'), ('left', 'Big left'), ('top', 'Big top'), ('cols', 'Columns'), ('rows', 'Rows')], onChanged: (v) => _upd(() => layout = v)),
            Seg<String>(label: 'Shape', value: shape, options: [for (final k in _shapes.keys) (k, k)], onChanged: (v) => _upd(() => shape = v)),
            SliderRow(label: 'Gap between pictures', value: gapPct, min: 0, max: 10, step: 1, display: '${gapPct.round()}%', onChanged: (v) => _upd(() => gapPct = v)),
            SliderRow(label: 'Outer space', value: padPct, min: 0, max: 10, step: 1, display: '${padPct.round()}%', onChanged: (v) => _upd(() => padPct = v)),
            SliderRow(label: 'Round the corners', value: radPct, min: 0, max: 15, step: 1, display: '${radPct.round()}%', onChanged: (v) => _upd(() => radPct = v)),
            ColorField(label: 'Background', value: bg, onChanged: (v) => _upd(() {
                  bg = v;
                  clearBg = false;
                })),
            Seg<Fmt>(label: 'Save as', value: fmt, options: const [(Fmt.jpeg, 'JPG'), (Fmt.png, 'PNG')], onChanged: (v) => _upd(() {
                  fmt = v;
                  if (v == Fmt.jpeg) clearBg = false;
                })),
            if (fmt == Fmt.png) Btn(clearBg ? '✓ Transparent background' : 'Transparent background', kind: clearBg ? BtnKind.zest : BtnKind.line, onTap: () => _upd(() => clearBg = !clearBg)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn(busy ? 'Working…' : 'Create collage', icon: Icons.dashboard_customize_outlined, onTap: busy ? null : _save),
          Btn('Clear', kind: BtnKind.line, onTap: () => _upd(() => pics.clear())),
        ]),
        if (out != null) ...[
          const SizedBox(height: 12),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(outName, style: body(14, w: FontWeight.w800)),
            Text(message, style: body(12, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: out!, name: outName, mime: kMime[fmt]!),
          ])),
        ],
      ],
    ]);
  }
}
