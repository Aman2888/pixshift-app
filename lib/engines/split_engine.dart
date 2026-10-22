// Split one picture into a grid of pieces (ZIP). Port of components/SplitTool.tsx.
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/files.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

class SplitEngine extends StatefulWidget {
  final Tool tool;
  const SplitEngine({super.key, required this.tool});
  @override
  State<SplitEngine> createState() => _SplitEngineState();
}

class _SplitEngineState extends State<SplitEngine> {
  Pic? pic;
  double rows = 1, cols = 3;
  bool busy = false;
  String error = '', message = '';
  Uint8List? zip;
  String zipName = '';

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept, multiple: false);
      if (got.isEmpty) return;
      setState(() {
        pic = got.first;
        error = '';
        zip = null;
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save() async {
    final p = pic;
    if (p == null) return;
    setState(() {
      busy = true;
      error = '';
      zip = null;
    });
    try {
      var fmt = formatFromName(p.name);
      if (fmt == Fmt.avif) fmt = Fmt.jpeg;
      final R = rows.round(), Cc = cols.round();
      final files = <MapEntry<String, Uint8List>>[];
      for (var r = 0; r < R; r++) {
        for (var c = 0; c < Cc; c++) {
          final x0 = (c * p.w / Cc).round(), x1 = ((c + 1) * p.w / Cc).round();
          final y0 = (r * p.h / R).round(), y1 = ((r + 1) * p.h / R).round();
          final w = x1 - x0, h = y1 - y0;
          final piece = await paint(w, h, (cv) => cv.drawImageRect(p.image, ui.Rect.fromLTWH(x0.toDouble(), y0.toDouble(), w.toDouble(), h.toDouble()), ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()));
          final bytes = await encodeImage(piece, fmt, fmt == Fmt.png ? 100 : 92);
          files.add(MapEntry('${baseName(p.name)}-r${r + 1}c${c + 1}.${kExt[fmt]}', bytes));
        }
      }
      setState(() {
        zip = zipFiles(files);
        zipName = '${baseName(p.name)}-split.zip';
        message = '${files.length} pieces in a ZIP.';
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
        Panel(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(builder: (ctx, c) {
            final aspect = p.w / p.h;
            var w = c.maxWidth, h = w / aspect;
            if (h > 420) {
              h = 420;
              w = h * aspect;
            }
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(fit: StackFit.expand, children: [
                  RawImage(image: p.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  CustomPaint(painter: _GridPainter(rows.round(), cols.round())),
                ]),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SliderRow(label: 'Columns', value: cols, min: 1, max: 10, step: 1, onChanged: (v) => setState(() {
                  cols = v;
                  zip = null;
                })),
            SliderRow(label: 'Rows', value: rows, min: 1, max: 10, step: 1, onChanged: (v) => setState(() {
                  rows = v;
                  zip = null;
                })),
            Text('${rows.round() * cols.round()} pieces', style: body(14, w: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 12),
        Btn(busy ? 'Working…' : 'Split into ${rows.round() * cols.round()} pieces', icon: Icons.grid_on, onTap: busy ? null : _save),
        if (zip != null) ...[
          const SizedBox(height: 12),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(zipName, style: body(14, w: FontWeight.w800)),
            Text('$message ${formatBytes(zip!.length)}', style: body(12, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: zip!, name: zipName, mime: 'application/zip', image: false),
          ])),
        ],
      ],
    ]);
  }
}

class _GridPainter extends CustomPainter {
  final int rows, cols;
  _GridPainter(this.rows, this.cols);
  @override
  void paint(Canvas canvas, Size s) {
    final dark = Paint()..color = const Color(0x990D2B24)..strokeWidth = 3;
    final white = Paint()..color = Colors.white..strokeWidth = 1.5;
    for (var i = 1; i < cols; i++) {
      final x = s.width * i / cols;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), dark);
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), white);
    }
    for (var i = 1; i < rows; i++) {
      final y = s.height * i / rows;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), dark);
      canvas.drawLine(Offset(0, y), Offset(s.width, y), white);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.rows != rows || old.cols != cols;
}
