// Favicon pack from one logo. Port of components/FaviconTool.tsx.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/files.dart';
import '../core/ico_pdf.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

const _sizes = [16, 32, 48, 180, 192, 512];

const _snippet = '''<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">''';

const _manifest = '''{
  "name": "",
  "short_name": "",
  "icons": [
    { "src": "/android-chrome-192x192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/android-chrome-512x512.png", "sizes": "512x512", "type": "image/png" }
  ],
  "display": "standalone"
}''';

Future<ui.Image> _drawIcon(ui.Image src, int size, String shape, double padPct, String bg, bool clear) {
  final r = shape == 'circle' ? size / 2 : shape == 'rounded' ? size * 0.22 : 0.0;
  return paint(size, size, (c) {
    final rect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    c.clipRRect(ui.RRect.fromRectXY(rect, r, r), doAntiAlias: true);
    if (!clear) c.drawRect(rect, ui.Paint()..color = colorOf(bg));
    final pad = padPct / 100 * size;
    final box = size - pad * 2;
    final s = math.min(box / src.width, box / src.height);
    final w = src.width * s, h = src.height * s;
    drawImageRect(c, src, ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), ui.Rect.fromLTWH((size - w) / 2, (size - h) / 2, w, h));
  });
}

class FaviconEngine extends StatefulWidget {
  final Tool tool;
  const FaviconEngine({super.key, required this.tool});
  @override
  State<FaviconEngine> createState() => _FaviconEngineState();
}

class _FaviconEngineState extends State<FaviconEngine> {
  Pic? pic;
  String shape = 'rounded', bg = '#ffffff';
  double pad = 8;
  bool clear = true, busy = false;
  String error = '', copied = '';
  Map<int, ui.Image> prevs = {};
  Uint8List? zip;
  int _tok = 0;

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept, multiple: false);
      if (got.isEmpty) return;
      setState(() {
        pic = got.first;
        error = '';
        zip = null;
      });
      _previews();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _previews() async {
    final p = pic;
    if (p == null) return;
    final t = ++_tok;
    final m = <int, ui.Image>{};
    for (final s in _sizes) {
      m[s] = await _drawIcon(p.image, s, shape, pad, bg, clear);
    }
    if (mounted && t == _tok) setState(() => prevs = m);
  }

  void _upd(VoidCallback f) {
    setState(() {
      f();
      zip = null;
    });
    _previews();
  }

  Future<void> _save() async {
    final p = pic;
    if (p == null) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final png = <int, Uint8List>{};
      for (final s in _sizes) {
        png[s] = await pngBytes(await _drawIcon(p.image, s, shape, pad, bg, clear));
      }
      final ico = buildIco([IcoImage(16, png[16]!), IcoImage(32, png[32]!), IcoImage(48, png[48]!)]);
      final z = zipFiles([
        MapEntry('favicon.ico', ico),
        MapEntry('favicon-16x16.png', png[16]!),
        MapEntry('favicon-32x32.png', png[32]!),
        MapEntry('apple-touch-icon.png', png[180]!),
        MapEntry('android-chrome-192x192.png', png[192]!),
        MapEntry('android-chrome-512x512.png', png[512]!),
        MapEntry('site.webmanifest', Uint8List.fromList(utf8.encode(_manifest))),
        MapEntry('paste-in-head.html', Uint8List.fromList(utf8.encode(_snippet))),
      ]);
      setState(() => zip = z);
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your icons', style: body(14, w: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.end, children: [
              for (final s in _sizes)
                if (prevs[s] != null)
                  Column(children: [
                    SizedBox(width: math.min(s, 96).toDouble(), height: math.min(s, 96).toDouble(), child: Checker(child: RawImage(image: prevs[s]!, fit: BoxFit.contain, filterQuality: FilterQuality.medium))),
                    const SizedBox(height: 4),
                    Text('$s×$s', style: body(11, color: C.muted)),
                  ]),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Seg<String>(label: 'Shape', value: shape, options: const [('square', 'Square'), ('rounded', 'Rounded'), ('circle', 'Circle')], onChanged: (v) => _upd(() => shape = v)),
            SliderRow(label: 'Space around logo', value: pad, min: 0, max: 30, display: '${pad.round()}%', onChanged: (v) => _upd(() => pad = v.roundToDouble())),
            ColorField(label: 'Background colour', value: bg, onChanged: (v) => _upd(() {
                  bg = v;
                  clear = false;
                })),
            Btn(clear ? '✓ Transparent background' : 'Transparent background', kind: clear ? BtnKind.zest : BtnKind.line, onTap: () => _upd(() => clear = !clear)),
          ]),
        ),
        const SizedBox(height: 12),
        Btn(busy ? 'Working…' : 'Create favicon pack', icon: Icons.emoji_objects_outlined, onTap: busy ? null : _save),
        if (zip != null) ...[
          const SizedBox(height: 12),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('favicons.zip', style: body(14, w: FontWeight.w800)),
            Text('${formatBytes(zip!.length)} · favicon.ico, PNG sizes, manifest and the HTML to paste', style: body(12, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: zip!, name: 'favicons.zip', mime: 'application/zip', image: false),
            const SizedBox(height: 8),
            Btn(copied == 'html' ? 'Copied!' : 'Copy the HTML for <head>', kind: BtnKind.line, onTap: () async {
              await copyText(_snippet);
              setState(() => copied = 'html');
            }),
          ])),
        ],
      ],
    ]);
  }
}
