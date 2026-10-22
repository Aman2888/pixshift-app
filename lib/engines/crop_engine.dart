// Crop and circle crop. Port of components/CropTool.tsx.
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

const _ratios = <(String, String, double?)>[
  ('free', 'Free', null), ('1:1', '1:1', 1), ('4:5', '4:5', 4 / 5), ('3:4', '3:4', 3 / 4),
  ('4:3', '4:3', 4 / 3), ('3:2', '3:2', 3 / 2), ('16:9', '16:9', 16 / 9), ('9:16', '9:16', 9 / 16),
];
const double _min = 0.04;

class CropEngine extends StatefulWidget {
  final Tool tool;
  const CropEngine({super.key, required this.tool});
  @override
  State<CropEngine> createState() => _CropEngineState();
}

class _CropEngineState extends State<CropEngine> {
  Pic? pic;
  late bool circle = widget.tool.mode == 'circle';
  late String ratio = circle ? '1:1' : 'free';
  Rect rect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8); // fractions of the picture
  bool busy = false;
  String error = '';
  Uint8List? out;
  String outName = '';

  double? get _r => _ratios.firstWhere((e) => e.$1 == ratio).$3;

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept, multiple: false);
      if (got.isEmpty) return;
      setState(() {
        pic = got.first;
        out = null;
        error = '';
        rect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
      });
      _applyRatio(ratio);
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Largest centred rectangle with the wanted shape.
  void _applyRatio(String id) {
    final p = pic;
    if (p == null) return;
    final r = _ratios.firstWhere((e) => e.$1 == id).$3;
    setState(() {
      ratio = id;
      if (r == null) return;
      final W = p.w.toDouble(), H = p.h.toDouble();
      var w = 0.8, h = w * W / (r * H);
      if (h > 0.8) {
        h = 0.8;
        w = h * r * H / W;
      }
      rect = Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
    });
  }

  Rect _clampRect(Rect r) {
    var l = r.left, t = r.top;
    l = l.clamp(0.0, 1 - r.width);
    t = t.clamp(0.0, 1 - r.height);
    return Rect.fromLTWH(l, t, r.width, r.height);
  }

  void _resize(int corner, Offset d, Size disp) {
    final p = pic!;
    final dx = d.dx / disp.width, dy = d.dy / disp.height;
    var l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    if (corner == 0 || corner == 2) {
      l += dx;
    } else {
      r += dx;
    }
    if (corner == 0 || corner == 1) {
      t += dy;
    } else {
      b += dy;
    }
    l = l.clamp(0.0, 1.0);
    r = r.clamp(0.0, 1.0);
    t = t.clamp(0.0, 1.0);
    b = b.clamp(0.0, 1.0);
    var w = math.max(_min, r - l), h = math.max(_min, b - t);
    final ra = _r;
    if (ra != null) {
      h = w * p.w / (ra * p.h);
      if (h > 1) {
        h = 1;
        w = h * ra * p.h / p.w;
      }
    }
    var nl = (corner == 0 || corner == 2) ? rect.right - w : rect.left;
    var nt = (corner == 0 || corner == 1) ? rect.bottom - h : rect.top;
    nl = nl.clamp(0.0, 1 - w);
    nt = nt.clamp(0.0, 1 - h);
    setState(() => rect = Rect.fromLTWH(nl, nt, w, h));
  }

  Future<void> _save() async {
    final p = pic;
    if (p == null) return;
    setState(() {
      busy = true;
      error = '';
      out = null;
    });
    try {
      final sx = (rect.left * p.w).round(), sy = (rect.top * p.h).round();
      final sw = math.max(1, (rect.width * p.w).round()), sh = math.max(1, (rect.height * p.h).round());
      final img = await paint(sw, sh, (c) {
        if (circle) {
          c.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble())), doAntiAlias: true);
        }
        drawImageRect(c, p.image, Rect.fromLTWH(sx.toDouble(), sy.toDouble(), sw.toDouble(), sh.toDouble()), Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()));
      });
      var f = circle ? Fmt.png : formatFromName(p.name);
      if (f == Fmt.avif) f = Fmt.jpeg;
      final bytes = await encodeImage(img, f, f == Fmt.png ? 100 : 92);
      setState(() {
        out = bytes;
        outName = '${baseName(p.name)}-${circle ? 'circle' : 'cropped'}-${sw}x$sh.${kExt[f]}';
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pic;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PickZone(icon: widget.tool.icon, name: widget.tool.name, acceptLabel: widget.tool.acceptLabel, count: p == null ? 0 : 1, multiple: false, onTap: _pick),
      const SizedBox(height: 12),
      if (error.isNotEmpty) ErrorBox(error),
      if (p != null) ...[
        Panel(padding: const EdgeInsets.all(8), child: LayoutBuilder(builder: (ctx, c) {
          final aspect = p.w / p.h;
          var w = c.maxWidth, h = w / aspect;
          if (h > 440) {
            h = 440;
            w = h * aspect;
          }
          final disp = Size(w, h);
          final box = Rect.fromLTWH(rect.left * w, rect.top * h, rect.width * w, rect.height * h);
          return Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: RawImage(image: p.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                Positioned.fill(child: CustomPaint(painter: _CropPainter(box, circle))),
                Positioned.fromRect(
                  rect: box,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (d) => setState(() => rect = _clampRect(rect.shift(Offset(d.delta.dx / w, d.delta.dy / h)))),
                  ),
                ),
                for (var i = 0; i < 4; i++)
                  Positioned(
                    left: (i % 2 == 0 ? box.left : box.right) - 22,
                    top: (i < 2 ? box.top : box.bottom) - 22,
                    child: GestureDetector(
                      onPanUpdate: (d) => _resize(i, d.delta, disp),
                      child: Container(width: 44, height: 44, color: Colors.transparent, alignment: Alignment.center, child: Container(width: 18, height: 18, decoration: BoxDecoration(color: C.zest, border: Border.all(color: C.pine, width: 2), borderRadius: BorderRadius.circular(5)))),
                    ),
                  ),
              ]),
            ),
          );
        })),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!circle) Seg<String>(label: 'Shape', value: ratio, options: [for (final r in _ratios) (r.$1, r.$2)], onChanged: _applyRatio),
            Text('Crop size: ${(rect.width * p.w).round()} × ${(rect.height * p.h).round()} px', style: body(14, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Drag inside the box to move it, drag the corners to resize.', style: body(12, color: C.muted)),
          ]),
        ),
        const SizedBox(height: 12),
        Btn(busy ? 'Working…' : (circle ? 'Create circle PNG' : 'Crop picture'), icon: Icons.crop, onTap: busy ? null : _save),
        if (out != null) ...[
          const SizedBox(height: 12),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(outName, style: body(14, w: FontWeight.w800)),
            Text(formatBytes(out!.length), style: body(12, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: out!, name: outName, mime: outName.endsWith('.png') ? 'image/png' : outName.endsWith('.webp') ? 'image/webp' : 'image/jpeg'),
          ])),
        ],
      ],
    ]);
  }
}

class _CropPainter extends CustomPainter {
  final Rect box;
  final bool circle;
  _CropPainter(this.box, this.circle);
  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0x990D2B24);
    final path = Path()..addRect(Offset.zero & size);
    path.addPath(circle ? (Path()..addOval(box)) : (Path()..addRect(box)), Offset.zero);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dim);
    final line = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2;
    if (circle) {
      canvas.drawOval(box, line);
    } else {
      canvas.drawRect(box, line);
      final g = Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(Offset(box.left + box.width * i / 3, box.top), Offset(box.left + box.width * i / 3, box.bottom), g);
        canvas.drawLine(Offset(box.left, box.top + box.height * i / 3), Offset(box.right, box.top + box.height * i / 3), g);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.box != box || old.circle != circle;
}
