// Combine several pictures into one. Port of components/CombineTool.tsx.
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

class _Cell {
  final Pic pic;
  final double x, y, w, h;
  _Cell(this.pic, this.x, this.y, this.w, this.h);
}

class _Plan {
  final List<_Cell> cells;
  final double W, H;
  _Plan(this.cells, this.W, this.H);
}

_Plan _plan(List<Pic> items, String layout, int cols, double gap) {
  final cells = <_Cell>[];
  if (items.isEmpty) return _Plan(cells, 1, 1);
  if (layout == 'row') {
    final H = items.map((i) => i.h).reduce(math.min).toDouble();
    var x = 0.0;
    for (final p in items) {
      final w = (p.w * H / p.h).roundToDouble();
      cells.add(_Cell(p, x, 0, w, H));
      x += w + gap;
    }
    return _Plan(cells, x - gap, H);
  }
  if (layout == 'column') {
    final W = items.map((i) => i.w).reduce(math.min).toDouble();
    var y = 0.0;
    for (final p in items) {
      final h = (p.h * W / p.w).roundToDouble();
      cells.add(_Cell(p, 0, y, W, h));
      y += h + gap;
    }
    return _Plan(cells, W, y - gap);
  }
  final c = math.max(1, math.min(cols, items.length));
  final rows = (items.length / c).ceil();
  final cw = items.map((i) => i.w).reduce(math.min).toDouble();
  final ch = items.map((i) => i.h).reduce(math.min).toDouble();
  for (var i = 0; i < items.length; i++) {
    final p = items[i];
    final col = i % c, row = i ~/ c;
    final s = math.min(cw / p.w, ch / p.h);
    final w = (p.w * s).roundToDouble(), h = (p.h * s).roundToDouble();
    cells.add(_Cell(p, col * (cw + gap) + (cw - w) / 2, row * (ch + gap) + (ch - h) / 2, w, h));
  }
  return _Plan(cells, c * cw + (c - 1) * gap, rows * ch + (rows - 1) * gap);
}

class CombineEngine extends StatefulWidget {
  final Tool tool;
  const CombineEngine({super.key, required this.tool});
  @override
  State<CombineEngine> createState() => _CombineEngineState();
}

class _CombineEngineState extends State<CombineEngine> {
  final List<Pic> pics = [];
  String layout = 'row', bg = '#ffffff';
  double cols = 2, gapPct = 2;
  bool clearBg = false;
  Fmt fmt = Fmt.jpeg;
  bool busy = false;
  String error = '', message = '';
  Uint8List? out;
  String outName = '';

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept);
      setState(() {
        pics.addAll(got);
        error = '';
        out = null;
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _make() async {
    if (pics.length < 2) {
      setState(() => error = 'Add at least two pictures to combine.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
      out = null;
    });
    try {
      final base = pics.map((p) => math.min(p.w, p.h)).reduce(math.min);
      final geo = _plan(pics, layout, cols.round(), (gapPct / 100 * base).roundToDouble());
      var scale = 1.0;
      while ((geo.W * scale > kMaxEdge || geo.H * scale > kMaxEdge || geo.W * geo.H * scale * scale > kMaxPixels) && scale > 0.05) {
        scale *= 0.9;
      }
      final w = math.max(1, (geo.W * scale).round()), h = math.max(1, (geo.H * scale).round());
      final transparent = clearBg && fmt == Fmt.png;
      final img = await paint(w, h, (c) {
        if (!transparent) c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = colorOf(bg));
        for (final cell in geo.cells) {
          drawImageRect(c, cell.pic.image, ui.Rect.fromLTWH(0, 0, cell.pic.w.toDouble(), cell.pic.h.toDouble()), ui.Rect.fromLTWH(cell.x * scale, cell.y * scale, cell.w * scale, cell.h * scale));
        }
      });
      final bytes = await encodeImage(img, fmt, fmt == Fmt.png ? 100 : 92, background: bg);
      setState(() {
        out = bytes;
        outName = 'pixshift-combined.${kExt[fmt]}';
        message = '$w×$h · ${formatBytes(bytes.length)}${scale < 1 ? ' · reduced to fit the phone limit' : ''}';
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
      if (error.isNotEmpty) ErrorBox(error),
      if (pics.isNotEmpty) ...[
        Text('Pictures, in order', style: body(14, w: FontWeight.w800)),
        const SizedBox(height: 6),
        PicStrip(
          pics: pics,
          onRemove: (p) => setState(() {
            pics.remove(p);
            out = null;
          }),
          onMove: (i, d) => setState(() {
            final p = pics.removeAt(i);
            pics.insert(i + d, p);
            out = null;
          }),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Seg<String>(label: 'Layout', value: layout, options: const [('row', 'Side by side'), ('column', 'Stacked'), ('grid', 'Grid')], onChanged: (v) => setState(() => layout = v)),
            if (layout == 'grid') SliderRow(label: 'Columns', value: cols, min: 2, max: 6, step: 1, onChanged: (v) => setState(() => cols = v)),
            SliderRow(label: 'Gap', value: gapPct, min: 0, max: 10, step: 1, display: '${gapPct.round()}%', onChanged: (v) => setState(() => gapPct = v)),
            ColorField(label: 'Background', value: bg, onChanged: (v) => setState(() {
                  bg = v;
                  clearBg = false;
                })),
            Seg<Fmt>(label: 'Save as', value: fmt, options: const [(Fmt.jpeg, 'JPG'), (Fmt.png, 'PNG')], onChanged: (v) => setState(() {
                  fmt = v;
                  if (v == Fmt.jpeg) clearBg = false;
                })),
            if (fmt == Fmt.png) Btn(clearBg ? '✓ Transparent background' : 'Transparent background', kind: clearBg ? BtnKind.zest : BtnKind.line, onTap: () => setState(() => clearBg = !clearBg)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn(busy ? 'Working…' : 'Combine ${pics.length} pictures', icon: Icons.view_agenda_outlined, onTap: busy ? null : _make),
          Btn('Clear', kind: BtnKind.line, onTap: () => setState(() {
                pics.clear();
                out = null;
              })),
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
