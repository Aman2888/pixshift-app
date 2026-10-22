// Meme maker (top and bottom text). Port of components/MemeTool.tsx.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/files.dart';
import '../core/ops.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

List<String> _wrap(String text, double size, double maxW) {
  final out = <String>[];
  for (final para in text.split('\n')) {
    var line = '';
    for (final word in para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      final test = line.isNotEmpty ? '$line $word' : word;
      if (line.isNotEmpty && measureText(test, size, family: 'impact') > maxW) {
        out.add(line);
        line = word;
      } else {
        line = test;
      }
    }
    out.add(line);
  }
  final res = <String>[];
  for (var i = 0; i < out.length; i++) {
    if (out[i].isNotEmpty || out.length == 1) res.add(out[i]);
  }
  return res;
}

Future<ui.Image> _drawMeme(ui.Image bmp, double scale, String top, String bottom, double sizeF, String color, bool caps) {
  final W = math.max(1, (bmp.width * scale).round()), H = math.max(1, (bmp.height * scale).round());
  return paint(W, H, (c) {
    drawImageRect(c, bmp, ui.Rect.fromLTWH(0, 0, bmp.width.toDouble(), bmp.height.toDouble()), ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
    final size = math.max(10.0, sizeF * math.min(W, H));
    final fill = colorOf(color);
    final stroke = color.toLowerCase() == '#000000' ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFF000000);
    final margin = size * 0.35;
    final lh = size * 1.08;
    void put(String t, bool fromTop) {
      final text = caps ? t.toUpperCase() : t;
      if (text.trim().isEmpty) return;
      final lines = _wrap(text, size, W - margin * 2);
      final startY = fromTop ? margin + size * 0.85 : H - margin - lh * (lines.length - 1) - size * 0.1;
      for (var i = 0; i < lines.length; i++) {
        final baseline = startY + i * lh;
        drawText(c, lines[i], size, fill, W / 2, baseline - size * 0.35, align: 'center', outline: stroke, outlineW: math.max(2.0, size / 7), family: 'impact', maxWidth: W - margin * 2);
      }
    }

    put(top, true);
    put(bottom, false);
  });
}

class MemeEngine extends StatefulWidget {
  final Tool tool;
  const MemeEngine({super.key, required this.tool});
  @override
  State<MemeEngine> createState() => _MemeEngineState();
}

class _MemeEngineState extends State<MemeEngine> {
  Pic? pic;
  final topC = TextEditingController(text: 'WHEN THE WIFI FINALLY WORKS');
  final botC = TextEditingController(text: 'AND YOU FORGOT WHY YOU NEEDED IT');
  double size = 0.1;
  String color = '#ffffff';
  bool caps = true, busy = false;
  Fmt fmt = Fmt.jpeg;
  String error = '';
  ui.Image? shown;
  Uint8List? out;
  String outName = '';
  int _tok = 0;

  @override
  void dispose() {
    topC.dispose();
    botC.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept, multiple: false);
      if (got.isEmpty) return;
      setState(() {
        pic = got.first;
        error = '';
        out = null;
      });
      _preview();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _preview() async {
    final p = pic;
    if (p == null) return;
    final t = ++_tok;
    final k = math.min(1.0, 900 / math.max(p.w, p.h));
    final img = await _drawMeme(p.image, k, topC.text, botC.text, size, color, caps);
    if (mounted && t == _tok) setState(() => shown = img);
  }

  void _upd(VoidCallback f) {
    setState(() {
      f();
      out = null;
    });
    _preview();
  }

  Future<void> _save() async {
    final p = pic;
    if (p == null) return;
    setState(() => busy = true);
    try {
      final s = math.min(1.0, 3000 / math.max(p.w, p.h));
      final img = await _drawMeme(p.image, s, topC.text, botC.text, size, color, caps);
      final bytes = await encodeImage(img, fmt, fmt == Fmt.png ? 100 : 92);
      setState(() {
        out = bytes;
        outName = 'pixshift-meme.${kExt[fmt]}';
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
        if (shown != null) Panel(padding: const EdgeInsets.all(8), child: Center(child: UiImageView(shown!, maxHeight: 440))),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Top text', style: body(14, color: C.ink2)),
            const SizedBox(height: 6),
            TextField(controller: topC, maxLines: 2, minLines: 1, onChanged: (_) => _upd(() {})),
            const SizedBox(height: 12),
            Text('Bottom text', style: body(14, color: C.ink2)),
            const SizedBox(height: 6),
            TextField(controller: botC, maxLines: 2, minLines: 1, onChanged: (_) => _upd(() {})),
            const SizedBox(height: 12),
            SliderRow(label: 'Text size', value: size, min: 0.04, max: 0.2, step: 0.005, display: '${(size * 100).round()}%', onChanged: (v) => _upd(() => size = v)),
            ColorField(label: 'Text colour', value: color, onChanged: (v) => _upd(() => color = v)),
            Row(children: [
              Switch(value: caps, activeColor: C.brand600, onChanged: (v) => _upd(() => caps = v)),
              Text('ALL CAPS', style: body(14)),
            ]),
            Seg<Fmt>(label: 'Save as', value: fmt, options: const [(Fmt.jpeg, 'JPG'), (Fmt.png, 'PNG')], onChanged: (v) => setState(() {
                  fmt = v;
                  out = null;
                })),
          ]),
        ),
        const SizedBox(height: 12),
        Btn(busy ? 'Working…' : 'Create meme', icon: Icons.emoji_emotions_outlined, onTap: busy ? null : _save),
        if (out != null) ...[
          const SizedBox(height: 12),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(outName, style: body(14, w: FontWeight.w800)),
            Text(formatBytes(out!.length), style: body(12, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: out!, name: outName, mime: kMime[fmt]!),
          ])),
        ],
      ],
    ]);
  }
}
