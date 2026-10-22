// Colour picker and palette extractor. Port of components/ColorTool.tsx.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../core/files.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

class ColorEngine extends StatefulWidget {
  final Tool tool;
  const ColorEngine({super.key, required this.tool});
  @override
  State<ColorEngine> createState() => _ColorEngineState();
}

class _ColorEngineState extends State<ColorEngine> {
  Pic? pic;
  Rgba? data; // downscaled copy used for lookups
  String error = '';
  Rgb? current;
  final List<Rgb> saved = [];
  double count = 6;
  List<Swatch> colors = [];
  String copied = '';
  bool get pickMode => widget.tool.mode != 'palette';

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept, multiple: false);
      if (got.isEmpty) return;
      final p = got.first;
      final s = math.min(1.0, 2400 / math.max(p.w, p.h));
      final small = s < 1 ? await scaleTo(p.image, math.max(1, (p.w * s).round()), math.max(1, (p.h * s).round())) : p.image;
      final d = await toRgba(small);
      setState(() {
        pic = p;
        data = d;
        error = '';
        saved.clear();
        current = null;
      });
      await _palette();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _palette() async {
    final p = pic;
    if (p == null || pickMode) return;
    final s = math.min(1.0, 200 / math.max(p.w, p.h));
    final small = await scaleTo(p.image, math.max(1, (p.w * s).round()), math.max(1, (p.h * s).round()));
    final d = await toRgba(small);
    setState(() => colors = palette(d.d, count.round()));
  }

  Rgb? _at(Offset o, Size size) {
    final d = data;
    if (d == null) return null;
    final x = (o.dx / size.width * d.w).floor().clamp(0, d.w - 1);
    final y = (o.dy / size.height * d.h).floor().clamp(0, d.h - 1);
    final i = (y * d.w + x) * 4;
    return [d.d[i].toDouble(), d.d[i + 1].toDouble(), d.d[i + 2].toDouble()];
  }

  Future<void> _copy(String text) async {
    await copyText(text);
    setState(() => copied = text);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && copied == text) setState(() => copied = '');
    });
  }

  Widget _swatch(Rgb c, String label) {
    final hex = toHex(c);
    final dark = darkInkOn(c);
    return InkWell(
      onTap: () => _copy(hex),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Color.fromARGB(255, c[0].round(), c[1].round(), c[2].round()), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 28),
          Text(copied == hex ? 'Copied!' : hex, style: body(14, color: dark ? C.pine : Colors.white, w: FontWeight.w800)),
          Text(label, style: body(11, color: dark ? C.pine : Colors.white)),
        ]),
      ),
    );
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
            final size = Size(w, h);
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: GestureDetector(
                  onTapUp: pickMode ? (d) => setState(() => current = _at(d.localPosition, size)) : null,
                  onPanUpdate: pickMode ? (d) => setState(() => current = _at(d.localPosition, size)) : null,
                  child: ClipRRect(borderRadius: BorderRadius.circular(12), child: RawImage(image: p.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        if (pickMode) ...[
          Panel(
            child: current == null
                ? Text('Tap or drag on the picture to pick a colour.', style: body(14, color: C.muted))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(height: 64, decoration: BoxDecoration(color: Color.fromARGB(255, current![0].round(), current![1].round(), current![2].round()), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line))),
                    const SizedBox(height: 12),
                    for (final r in [
                      ['HEX', toHex(current!)],
                      ['RGB', 'rgb(${current!.map((e) => e.round()).join(', ')})'],
                      ['HSL', 'hsl(${toHsl(current!)[0]}, ${toHsl(current!)[1]}%, ${toHsl(current!)[2]}%)'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          SizedBox(width: 44, child: Text(r[0], style: body(13, color: C.muted))),
                          Expanded(child: Text(r[1], style: body(14, w: FontWeight.w800))),
                          TextButton(onPressed: () => _copy(r[1]), child: Text(copied == r[1] ? 'Copied!' : 'Copy')),
                        ]),
                      ),
                    Btn('Save this colour', kind: BtnKind.zest, onTap: () => setState(() {
                      if (!saved.any((s) => toHex(s) == toHex(current!))) saved.add(current!);
                    })),
                  ]),
          ),
          if (saved.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Saved colours', style: display(18)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in saved) _swatch(s, 'tap to copy')]),
          ],
        ] else ...[
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SliderRow(label: 'Number of colours', value: count, min: 3, max: 12, onChanged: (v) {
                setState(() => count = v.roundToDouble());
                _palette();
              }),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final s in colors) _swatch(s.rgb, '${(s.share * 100).round()}% of the picture')]),
              if (colors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Btn('Copy all HEX codes', kind: BtnKind.line, onTap: () => _copy(colors.map((e) => toHex(e.rgb)).join(', '))),
              ],
            ]),
          ),
        ],
      ],
    ]);
  }
}
