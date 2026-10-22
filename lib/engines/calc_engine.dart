// Calculators: aspect ratio, DPI, pixels<->inches, file size. Port of AspectCalculator.tsx and Calculators.tsx.
import 'package:flutter/material.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

const _unitIn = {'in': 1.0, 'cm': 1 / 2.54, 'mm': 1 / 25.4};
String _f(double? n, [int d = 2]) {
  if (n == null || n.isNaN || n.isInfinite) return '–';
  final m = n * _pow10(d);
  final r = m.round() / _pow10(d);
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

double _pow10(int d) => d == 0 ? 1 : (d == 1 ? 10 : 100);

class CalcEngine extends StatelessWidget {
  final Tool tool;
  const CalcEngine({super.key, required this.tool});
  @override
  Widget build(BuildContext context) {
    switch (tool.calc) {
      case 'aspect':
        return const _Aspect();
      case 'dpi':
        return const _Dpi();
      case 'px-to-in':
        return const _PxToIn();
      case 'in-to-px':
        return const _InToPx();
      default:
        return const _FileSize();
    }
  }
}

Widget _result(List<Widget> kids) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(color: C.zest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.pine, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
    );

Widget _hintText(String s) => Text(s, style: body(14, color: C.muted));

class _DpiPick extends StatelessWidget {
  final double? value;
  final ValueChanged<double?> onChanged;
  const _DpiPick({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NumField(label: 'DPI (pixels per inch)', value: value, onChanged: onChanged),
        Wrap(spacing: 8, children: [
          for (final d in [72, 96, 150, 300, 600])
            ChoiceChip(label: Text('$d'), selected: value == d, selectedColor: C.zest, onSelected: (_) => onChanged(d.toDouble())),
        ]),
        const SizedBox(height: 8),
      ]);
}

class _Aspect extends StatefulWidget {
  const _Aspect();
  @override
  State<_Aspect> createState() => _AspectState();
}

class _AspectState extends State<_Aspect> {
  double? w = 1920, h = 1080, nw = 1280, nh;
  static const common = [('16:9', 16, 9), ('4:3', 4, 3), ('3:2', 3, 2), ('1:1', 1, 1), ('4:5', 4, 5), ('9:16', 9, 16), ('21:9', 21, 9)];
  @override
  Widget build(BuildContext context) {
    final ok = w != null && h != null && w! > 0 && h! > 0;
    final g = ok ? gcd(w!, h!) : 1;
    final resH = ok && nw != null ? (nw! * h! / w!).round() : null;
    final resW = ok && nh != null ? (nh! * w! / h!).round() : null;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: NumField(label: 'Width', suffix: 'px', value: w, onChanged: (v) => setState(() => w = v))),
          const SizedBox(width: 12),
          Expanded(child: NumField(label: 'Height', suffix: 'px', value: h, onChanged: (v) => setState(() => h = v))),
        ]),
        Wrap(spacing: 8, children: [
          for (final c in common)
            ActionChip(label: Text(c.$1), onPressed: () => setState(() {
                  final base = w ?? 1920;
                  w = base;
                  h = (base * c.$3 / c.$2).roundToDouble();
                })),
        ]),
        const SizedBox(height: 12),
        if (ok)
          _result([
            Text('${(w! / g).round()}:${(h! / g).round()}', style: display(28)),
            Text('Decimal ${(w! / h!).toStringAsFixed(3)}', style: body(14)),
          ])
        else
          _hintText('Enter a width and a height.'),
        const SizedBox(height: 8),
        Text('Resize and keep the ratio', style: display(18)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: NumField(label: 'New width', suffix: 'px', value: nw, onChanged: (v) => setState(() => nw = v))),
          const SizedBox(width: 12),
          Expanded(child: NumField(label: 'New height', suffix: 'px', value: nh, onChanged: (v) => setState(() => nh = v))),
        ]),
        if (resH != null) _result([Text('$resH px high for ${_f(nw, 0)} px wide', style: body(15, w: FontWeight.w800))]),
        if (resW != null) _result([Text('$resW px wide for ${_f(nh, 0)} px high', style: body(15, w: FontWeight.w800))]),
      ]),
    );
  }
}

class _Dpi extends StatefulWidget {
  const _Dpi();
  @override
  State<_Dpi> createState() => _DpiState();
}

class _DpiState extends State<_Dpi> {
  double? pw = 3000, ph = 2000, w = 10, h, want = 300;
  String unit = 'in';
  @override
  Widget build(BuildContext context) {
    final k = _unitIn[unit]!;
    final dpi = pw != null && w != null && w! > 0 ? pw! / (w! * k) : null;
    final hDpi = ph != null && h != null && h! > 0 ? ph! / (h! * k) : null;
    List<String> rate(double d) => d >= 300
        ? ['Excellent', 'Sharp prints at close range.']
        : d >= 200
            ? ['Good', 'Fine for most prints.']
            : d >= 150
                ? ['Fair', 'OK for posters seen from a distance.']
                : ['Low', 'Prints will look soft. Print smaller or use a bigger image.'];
    final needW = w != null && want != null ? (w! * k * want!).round() : null;
    final needH = h != null && want != null ? (h! * k * want!).round() : null;
    return Column(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1. What DPI will my print have?', style: display(18)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: NumField(label: 'Image width', suffix: 'px', value: pw, onChanged: (v) => setState(() => pw = v))),
            const SizedBox(width: 12),
            Expanded(child: NumField(label: 'Image height', suffix: 'px', value: ph, onChanged: (v) => setState(() => ph = v))),
          ]),
          Seg<String>(label: 'Print size unit', value: unit, options: const [('in', 'inches'), ('cm', 'cm'), ('mm', 'mm')], onChanged: (v) => setState(() => unit = v)),
          Row(children: [
            Expanded(child: NumField(label: 'Print width', suffix: unit, value: w, onChanged: (v) => setState(() => w = v))),
            const SizedBox(width: 12),
            Expanded(child: NumField(label: 'Print height', suffix: unit, value: h, onChanged: (v) => setState(() => h = v))),
          ]),
          if (dpi != null)
            _result([
              Text('${_f(dpi, 0)} DPI', style: display(26)),
              Text('${rate(dpi)[0]}. ${rate(dpi)[1]}', style: body(14)),
              if (hDpi != null && (hDpi - dpi).abs() / dpi > 0.02) Text('Height gives ${_f(hDpi, 0)} DPI, so the shape differs from your image. Keep the same ratio.', style: body(12)),
            ])
          else
            _hintText('Enter the image pixels and a print width.'),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('2. How many pixels do I need?', style: display(18)),
          const SizedBox(height: 6),
          _hintText('Uses the print size above.'),
          const SizedBox(height: 8),
          _DpiPick(value: want, onChanged: (v) => setState(() => want = v)),
          if (needW != null || needH != null)
            _result([
              Text('${needW != null ? '$needW px wide' : ''}${needW != null && needH != null ? ' × ' : ''}${needH != null ? '$needH px high' : ''}', style: display(22)),
              Text('for ${_f(w, 2)}${h != null ? ' × ${_f(h, 2)}' : ''} $unit at ${_f(want, 0)} DPI', style: body(14)),
            ])
          else
            _hintText('Enter a print width or height above.'),
        ]),
      ),
    ]);
  }
}

class _PxToIn extends StatefulWidget {
  const _PxToIn();
  @override
  State<_PxToIn> createState() => _PxToInState();
}

class _PxToInState extends State<_PxToIn> {
  double? w = 1800, h = 1200, dpi = 300;
  List<double>? rows(double? v) => v != null && dpi != null && dpi! > 0 ? [v / dpi!, v / dpi! * 2.54, v / dpi! * 25.4] : null;
  @override
  Widget build(BuildContext context) {
    final rw = rows(w), rh = rows(h);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pixels to inches, cm and mm', style: display(18)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: NumField(label: 'Width', suffix: 'px', value: w, onChanged: (v) => setState(() => w = v))),
          const SizedBox(width: 12),
          Expanded(child: NumField(label: 'Height (optional)', suffix: 'px', value: h, onChanged: (v) => setState(() => h = v))),
        ]),
        _DpiPick(value: dpi, onChanged: (v) => setState(() => dpi = v)),
        if (rw != null)
          _result([
            Text('${_f(rw[0])} in${rh != null ? ' × ${_f(rh[0])} in' : ''}', style: display(24)),
            Text('${_f(rw[1])} cm${rh != null ? ' × ${_f(rh[1])} cm' : ''} · ${_f(rw[2], 1)} mm${rh != null ? ' × ${_f(rh[2], 1)} mm' : ''}', style: body(14)),
          ])
        else
          _hintText('Enter pixels and a DPI.'),
      ]),
    );
  }
}

class _InToPx extends StatefulWidget {
  const _InToPx();
  @override
  State<_InToPx> createState() => _InToPxState();
}

class _InToPxState extends State<_InToPx> {
  String unit = 'in';
  double? w = 4, h = 6, dpi = 300;
  @override
  Widget build(BuildContext context) {
    final k = _unitIn[unit]!;
    final pw = w != null && dpi != null ? (w! * k * dpi!).round() : null;
    final ph = h != null && dpi != null ? (h! * k * dpi!).round() : null;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Inches, cm or mm to pixels', style: display(18)),
        const SizedBox(height: 10),
        Seg<String>(label: 'Unit', value: unit, options: const [('in', 'inches'), ('cm', 'cm'), ('mm', 'mm')], onChanged: (v) => setState(() => unit = v)),
        Row(children: [
          Expanded(child: NumField(label: 'Width', suffix: unit, value: w, onChanged: (v) => setState(() => w = v))),
          const SizedBox(width: 12),
          Expanded(child: NumField(label: 'Height (optional)', suffix: unit, value: h, onChanged: (v) => setState(() => h = v))),
        ]),
        _DpiPick(value: dpi, onChanged: (v) => setState(() => dpi = v)),
        if (pw != null)
          _result([
            Text('$pw px${ph != null ? ' × $ph px' : ''}', style: display(24)),
            if (ph != null) Text('${_f(pw * ph / 1e6, 1)} megapixels', style: body(14)),
          ])
        else
          _hintText('Enter a size and a DPI.'),
      ]),
    );
  }
}

class _FileSize extends StatefulWidget {
  const _FileSize();
  @override
  State<_FileSize> createState() => _FileSizeState();
}

class _FileSizeState extends State<_FileSize> {
  double? w = 4000, h = 3000;
  int depth = 24;
  String ratio = 'jpg75';
  static const ratios = [('none', 'None (raw)', 1.0), ('png', 'PNG (lossless)', 2.0), ('jpg90', 'JPG high quality', 8.0), ('jpg75', 'JPG medium', 16.0), ('webp', 'WebP / AVIF', 22.0)];
  @override
  Widget build(BuildContext context) {
    final raw = w != null && h != null ? w! * h! * depth / 8 : null;
    final r = ratios.firstWhere((e) => e.$1 == ratio).$3;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Estimate image file size', style: display(18)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: NumField(label: 'Width', suffix: 'px', value: w, onChanged: (v) => setState(() => w = v))),
          const SizedBox(width: 12),
          Expanded(child: NumField(label: 'Height', suffix: 'px', value: h, onChanged: (v) => setState(() => h = v))),
        ]),
        Wrap(spacing: 8, children: [
          for (final p in [('HD', 1280.0, 720.0), ('Full HD', 1920.0, 1080.0), ('4K', 3840.0, 2160.0), ('12 MP', 4000.0, 3000.0)])
            ActionChip(label: Text(p.$1), onPressed: () => setState(() {
                  w = p.$2;
                  h = p.$3;
                })),
        ]),
        const SizedBox(height: 12),
        Seg<int>(label: 'Colour depth', value: depth, options: const [(8, 'Grey 8-bit'), (24, 'Colour 24-bit'), (32, 'With alpha 32-bit')], onChanged: (v) => setState(() => depth = v)),
        Seg<String>(label: 'Compression', value: ratio, options: [for (final e in ratios) (e.$1, e.$2)], onChanged: (v) => setState(() => ratio = v)),
        if (raw != null)
          _result([
            Text('≈ ${formatBytes(raw / r)}', style: display(24)),
            Text('Raw pixel data is ${formatBytes(raw)}. Compressed sizes are estimates; real files vary with the picture.', style: body(13)),
          ])
        else
          _hintText('Enter width and height.'),
      ]),
    );
  }
}
