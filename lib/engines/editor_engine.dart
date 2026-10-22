// All pixel edits (rotate, watermark, filters, background tools, brush tools ...). Port of components/Editor.tsx.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/exif.dart';
import '../core/files.dart';
import '../core/ops.dart';
import '../core/ops_pixel.dart' show kFilterNames;
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

Map<String, dynamic> _defaults(String op) {
  switch (op) {
    case 'rotate':
      return {'quarter': 0, 'flipH': false, 'flipV': false, 'angle': 0.0, 'bg': 'transparent'};
    case 'watermark':
      return {'text': '© Your name', 'size': 0.06, 'opacity': 0.5, 'pos': 'br', 'color': '#ffffff', 'angle': -30.0};
    case 'enhance':
      return {'auto': true, 'brightness': 0.0, 'contrast': 0.0, 'saturation': 0.0, 'warmth': 0.0};
    case 'sharpen':
      return {'amount': 1.0, 'radius': 2.0};
    case 'bw':
      return {'contrast': 0.0, 'threshold': false, 'level': 128.0};
    case 'upscale':
      return {'factor': 2.0, 'sharp': 0.6};
    case 'blurbg':
      return {'cx': 0.5, 'cy': 0.5, 'size': 0.5, 'blur': 0.03, 'feather': 0.4};
    case 'redact':
      return {'style': 'pixelate', 'strength': 0.03};
    case 'bgremove':
      return {'tolerance': 30.0, 'softness': 1.0};
    case 'bgchange':
      return {'tolerance': 30.0, 'softness': 1.0, 'fill': '#ffffff'};
    case 'transparent':
      return {'tolerance': 30.0, 'px': 0.0, 'py': 0.0, 'hasPick': false, 'contiguous': false};
    case 'border':
      return {'width': 0.03, 'color': '#ffffff', 'radius': 0.0};
    case 'filter':
      return {'preset': 'sepia', 'strength': 1.0};
    case 'invert':
      return {'strength': 1.0};
    case 'blur':
      return {'amount': 0.02};
    case 'sketch':
      return {'detail': 0.02, 'darkness': 1.0};
    case 'pixel':
      return {'size': 0.02, 'levels': 0.0};
    case 'vignette':
      return {'strength': 0.6, 'size': 0.55, 'tone': 'dark'};
    case 'text':
      return {'text': 'Your text', 'size': 0.08, 'color': '#ffffff', 'pos': 'bc', 'font': 'impact', 'outline': true, 'bar': false};
    case 'pad':
      return {'ratio': '1:1', 'fill': 'blur', 'color': '#ffffff', 'margin': 0.0};
  }
  return {};
}

const Map<String, Map<String, dynamic>> _modeInit = {
  'flipH': {'flipH': true},
  'flipV': {'flipV': true},
  'manual': {'auto': false},
  'sepia': {'preset': 'sepia'},
  'vintage': {'preset': 'vintage'},
  'noir': {'preset': 'noir'},
  'ratio45': {'ratio': '4:5'},
  'ratio916': {'ratio': '9:16'},
  'ratio169': {'ratio': '16:9'},
};

const Map<String, String> _suffix = {
  'rotate': 'rotated', 'watermark': 'watermarked', 'exif': 'clean', 'enhance': 'enhanced', 'sharpen': 'sharp', 'bw': 'bw',
  'upscale': 'upscaled', 'blurbg': 'blur-bg', 'inpaint': 'cleaned', 'redact': 'redacted', 'bgremove': 'no-bg',
  'bgchange': 'new-bg', 'transparent': 'transparent', 'border': 'framed', 'filter': 'filtered', 'invert': 'inverted',
  'blur': 'blurred', 'sketch': 'sketch', 'pixel': 'pixelated', 'vignette': 'vignette', 'text': 'text', 'pad': 'padded',
};

const _brush = ['inpaint', 'redact'];
const _single = ['inpaint', 'redact', 'blurbg', 'transparent'];
const _pos = ['tl', 'tc', 'tr', 'ml', 'mc', 'mr', 'bl', 'bc', 'br'];

class _Item {
  final Pic pic;
  final ui.Image prev0; // small copy used for the live preview
  ui.Image base; // preview with locked-in brush edits
  final List<List<Stroke>> applied = [];
  _Item(this.pic, this.prev0) : base = prev0;
}

class _Out {
  final String name;
  final Uint8List bytes;
  final String mime;
  _Out(this.name, this.bytes, this.mime);
}

Future<ui.Image> _shrink(ui.Image src) async {
  final s = math.min(1.0, 900 / math.max(src.width, src.height));
  if (s >= 1) return src;
  return scaleTo(src, math.max(1, (src.width * s).round()), math.max(1, (src.height * s).round()));
}

class EditorEngine extends StatefulWidget {
  final Tool tool;
  const EditorEngine({super.key, required this.tool});
  @override
  State<EditorEngine> createState() => _EditorEngineState();
}

class _EditorEngineState extends State<EditorEngine> {
  late final String op = widget.tool.op!;
  late final bool brush = _brush.contains(op);
  late final bool single = _single.contains(op);
  final List<_Item> items = [];
  String activeId = '';
  late Map<String, dynamic> params = {..._defaults(op), ...(widget.tool.mode != null ? (_modeInit[widget.tool.mode] ?? {}) : {})};
  List<Stroke> strokes = [];
  double brushR = 0.035;
  String fmtPick = 'same';
  late double quality = op == 'exif' ? 95 : 92;
  bool busy = false;
  String message = '', error = '';
  Exif? exif;
  bool exifRead = false;
  ui.Image? shown;
  Timer? _deb;
  int _tok = 0;
  List<_Out> outs = [];
  late final TextEditingController _textCtrl = TextEditingController(text: params['text']?.toString() ?? '');

  _Item? get active {
    for (final i in items) {
      if (i.pic.id == activeId) return i;
    }
    return items.isEmpty ? null : items.first;
  }

  @override
  void dispose() {
    _deb?.cancel();
    _tok++;
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept, multiple: !single);
      if (got.isEmpty) return;
      final add = <_Item>[];
      for (final p in got) {
        add.add(_Item(p, await _shrink(p.image)));
      }
      setState(() {
        error = '';
        outs = [];
        message = '';
        if (single) items.clear();
        items.addAll(add);
        activeId = items.first.pic.id;
        strokes = [];
      });
      _afterActiveChange();
      _preview();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _afterActiveChange() {
    final a = active;
    if (a != null && op == 'exif') {
      final e = parseExif(a.pic.bytes);
      setState(() {
        exif = e;
        exifRead = true;
      });
    }
  }

  void _set(String k, dynamic v) {
    setState(() => params[k] = v);
    _preview();
  }

  void _preview({bool now = false}) {
    _deb?.cancel();
    _deb = Timer(Duration(milliseconds: now ? 5 : 150), () async {
      final a = active;
      if (a == null) return;
      final t = ++_tok;
      try {
        final r = await render(op, a.base, params, strokes);
        if (t == _tok && mounted) setState(() => shown = r);
      } catch (e) {
        if (t == _tok && mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    });
  }

  Future<void> _commit() async {
    final a = active;
    if (a == null || strokes.isEmpty) return;
    final r = await render(op, a.base, params, strokes);
    setState(() {
      a.base = r;
      a.applied.add(List<Stroke>.from(strokes));
      strokes = [];
      shown = r;
    });
  }

  Future<void> _undo() async {
    final a = active;
    if (a == null) return;
    if (strokes.isNotEmpty) {
      setState(() => strokes = strokes.sublist(0, strokes.length - 1));
      _preview(now: true);
      return;
    }
    if (a.applied.isEmpty) return;
    a.applied.removeLast();
    var cur = a.prev0;
    for (final s in a.applied) {
      cur = await render(op, cur, params, s);
    }
    setState(() {
      a.base = cur;
      shown = cur;
    });
  }

  bool get _canUndo => strokes.isNotEmpty || (active?.applied.isNotEmpty ?? false);

  Fmt _outFmt(Pic p) {
    var f = fmtPick == 'same' ? formatFromName(p.name) : (fmtFromString(fmtPick) ?? Fmt.jpeg);
    if (f == Fmt.avif) f = Fmt.jpeg;
    if (needsAlpha(op, params) && f == Fmt.jpeg) f = Fmt.png;
    return f;
  }

  Future<void> _export() async {
    if (items.isEmpty) return;
    setState(() {
      busy = true;
      error = '';
      message = '';
      outs = [];
    });
    try {
      final targets = single ? [active!] : items;
      final res = <_Out>[];
      for (final it in targets) {
        ui.Image full = it.pic.image;
        if (brush) {
          for (final s in it.applied) {
            full = await render(op, full, params, s);
          }
          if (strokes.isNotEmpty && it == active) full = await render(op, full, params, strokes);
        } else {
          full = await render(op, full, params);
        }
        final f = _outFmt(it.pic);
        final bytes = await encodeImage(full, f, f == Fmt.png ? 100 : quality.round());
        res.add(_Out('${baseName(it.pic.name)}-${_suffix[op]}.${kExt[f]}', bytes, kMime[f]!));
      }
      setState(() {
        outs = res;
        message = res.length == 1 ? 'Ready. Save your picture below.' : '${res.length} pictures ready.';
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = active;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PickZone(icon: widget.tool.icon, name: widget.tool.name, acceptLabel: widget.tool.acceptLabel, count: items.length, multiple: !single, onTap: _pick),
      const SizedBox(height: 12),
      if (error.isNotEmpty) ErrorBox(error),
      if (a != null) ...[
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PicStrip(
              pics: items.map((e) => e.pic).toList(),
              activeId: a.pic.id,
              onSelect: (p) {
                setState(() {
                  activeId = p.id;
                  strokes = [];
                  shown = null;
                });
                _afterActiveChange();
                _preview(now: true);
              },
              onRemove: (p) {
                setState(() {
                  items.removeWhere((e) => e.pic.id == p.id);
                  if (items.isNotEmpty) activeId = items.first.pic.id;
                  shown = null;
                });
                _preview(now: true);
              },
            ),
          ),
        Panel(padding: const EdgeInsets.all(8), child: _canvasArea(a)),
        const SizedBox(height: 12),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [..._controls(), ..._saveControls()])),
        const SizedBox(height: 12),
        Btn(busy ? 'Working…' : (single || items.length == 1 ? 'Create final picture' : 'Create ${items.length} pictures'), kind: BtnKind.dark, icon: Icons.check_circle_outline, onTap: busy ? null : _export),
        const SizedBox(height: 12),
        if (message.isNotEmpty) InfoBox(message),
        for (final o in outs)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.lineSoft)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.name, style: body(14, w: FontWeight.w800)),
              Text(formatBytes(o.bytes.length), style: body(12, color: C.muted)),
              const SizedBox(height: 8),
              OutputBar(bytes: o.bytes, name: o.name, mime: o.mime),
            ]),
          ),
        if (outs.length > 1)
          Btn('Save all as ZIP', icon: Icons.folder_zip_outlined, onTap: () async {
            await saveToDevice(zipFiles([for (final o in outs) MapEntry(o.name, o.bytes)]), 'pixshift-${_suffix[op]}.zip');
          }),
      ],
    ]);
  }

  /* ───────── preview area with touch handling ───────── */

  Widget _canvasArea(_Item a) {
    final img = shown ?? a.base;
    return LayoutBuilder(builder: (ctx, c) {
      final aspect = img.width / img.height;
      var w = c.maxWidth;
      var h = w / aspect;
      const maxH = 420.0;
      if (h > maxH) {
        h = maxH;
        w = h * aspect;
      }
      Offset norm(Offset o) => Offset((o.dx / w).clamp(0.0, 1.0), (o.dy / h).clamp(0.0, 1.0));
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Checker(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final n = norm(d.localPosition);
                  if (op == 'transparent') {
                    setState(() {
                      params['px'] = n.dx;
                      params['py'] = n.dy;
                      params['hasPick'] = true;
                    });
                    _preview();
                  } else if (op == 'blurbg') {
                    setState(() {
                      params['cx'] = n.dx;
                      params['cy'] = n.dy;
                    });
                    _preview();
                  } else if (brush) {
                    setState(() => strokes = [...strokes, Stroke([[n.dx, n.dy]], brushR)]);
                    _preview();
                  }
                },
                onPanStart: (d) {
                  final n = norm(d.localPosition);
                  if (brush) {
                    setState(() => strokes = [...strokes, Stroke([[n.dx, n.dy]], brushR)]);
                  } else if (op == 'blurbg') {
                    setState(() {
                      params['cx'] = n.dx;
                      params['cy'] = n.dy;
                    });
                  }
                },
                onPanUpdate: (d) {
                  final n = norm(d.localPosition);
                  if (brush && strokes.isNotEmpty) {
                    setState(() => strokes.last.pts.add([n.dx, n.dy]));
                  } else if (op == 'blurbg') {
                    setState(() {
                      params['cx'] = n.dx;
                      params['cy'] = n.dy;
                    });
                    _preview();
                  }
                },
                onPanEnd: (_) => _preview(now: true),
                child: Stack(fit: StackFit.expand, children: [
                  RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  if (brush && strokes.isNotEmpty) CustomPaint(painter: _StrokePainter(strokes)),
                  if (op == 'blurbg') CustomPaint(painter: _FocusPainter(num0(params, 'cx', 0.5), num0(params, 'cy', 0.5), num0(params, 'size', 0.5))),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }

  /* ───────── controls ───────── */

  Widget _sl(String label, String key, double min, double max, {double? step, String Function(double v)? disp, String? hint}) {
    final v = num0(params, key, min);
    return SliderRow(label: label, value: v, min: min, max: max, step: step, display: disp?.call(v), hint: hint, onChanged: (x) => _set(key, x));
  }

  String _pct(double v) => '${(v * 100).round()}%';

  Widget _posGrid() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Position', style: body(14, color: C.ink2)),
          const SizedBox(height: 8),
          SizedBox(
            width: 150,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.4,
              children: [
                for (final p in _pos)
                  InkWell(
                    onTap: () => _set('pos', p),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: params['pos'] == p ? C.zest : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: params['pos'] == p ? C.pine : C.line)),
                      child: Text(params['pos'] == p ? '●' : '·', style: body(18, w: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );

  Widget _textField(String label, {int maxLines = 1, int maxLength = 80}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: body(14, color: C.ink2)),
          const SizedBox(height: 6),
          TextField(controller: _textCtrl, maxLines: maxLines, minLines: maxLines, maxLength: maxLength, onChanged: (v) => _set('text', v)),
        ]),
      );

  Widget _switch(String label, String key) => Row(children: [
        Switch(value: params[key] == true, activeColor: C.brand600, onChanged: (v) => _set(key, v)),
        Expanded(child: Text(label, style: body(14))),
      ]);

  List<Widget> _controls() {
    switch (op) {
      case 'rotate':
        return [
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('⟲ 90° left', kind: BtnKind.line, onTap: () => _set('quarter', ((params['quarter'] as int) + 3) % 4)),
            Btn('⟳ 90° right', kind: BtnKind.line, onTap: () => _set('quarter', ((params['quarter'] as int) + 1) % 4)),
            Btn('⇋ Flip horizontal', kind: BtnKind.line, onTap: () => _set('flipH', params['flipH'] != true)),
            Btn('⇅ Flip vertical', kind: BtnKind.line, onTap: () => _set('flipV', params['flipV'] != true)),
          ]),
          const SizedBox(height: 12),
          _sl('Straighten', 'angle', -45, 45, step: 0.5, disp: (v) => '$v°'),
          Seg<String>(label: 'Empty corners', value: params['bg'] == 'transparent' ? 'transparent' : 'white', options: const [('transparent', 'Transparent (PNG)'), ('white', 'White')], onChanged: (v) => _set('bg', v == 'white' ? '#ffffff' : 'transparent')),
        ];
      case 'watermark':
        return [
          _textField('Watermark text'),
          _sl('Size', 'size', 0.02, 0.2, step: 0.005, disp: _pct),
          _sl('Opacity', 'opacity', 0.1, 1, step: 0.05, disp: _pct),
          ColorField(label: 'Text colour', value: params['color'], onChanged: (v) => _set('color', v)),
          if (params['pos'] != 'tile') _posGrid(),
          Btn(params['pos'] == 'tile' ? '✓ Tiled across the picture' : 'Tile across the picture', kind: params['pos'] == 'tile' ? BtnKind.zest : BtnKind.line, onTap: () => _set('pos', params['pos'] == 'tile' ? 'br' : 'tile')),
          const SizedBox(height: 12),
        ];
      case 'exif':
        return [
          Text('Hidden data found in this photo', style: body(15, w: FontWeight.w800)),
          const SizedBox(height: 8),
          if (!exifRead) Text('Reading…', style: body(14, color: C.muted)),
          if (exifRead && exif == null) Text('Nothing readable found. It may already be clean, or it is not a JPG. The clean copy is still saved without any metadata.', style: body(14, color: C.ink2)),
          if (exif != null)
            for (final r in [
              ['Camera', [exif!.make, exif!.model].whereType<String>().join(' ')],
              ['Taken', formatTaken(exif!.taken) ?? ''],
              ['Lens', exif!.lens ?? ''],
              ['Software', exif!.software ?? ''],
              ['Location', exif!.lat != null && exif!.lon != null ? formatCoords(exif!.lat!, exif!.lon!) : ''],
            ])
              if (r[1].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r[0], style: body(14, color: C.muted)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(r[1], textAlign: TextAlign.right, style: body(14, w: FontWeight.w700))),
                  ]),
                ),
          const SizedBox(height: 8),
          Text('The saved copy has all of this removed.', style: body(12, color: C.muted)),
          const SizedBox(height: 12),
        ];
      case 'enhance':
        return [
          _switch('Auto-fix brightness (levels)', 'auto'),
          _sl('Brightness', 'brightness', -60, 60),
          _sl('Contrast', 'contrast', -60, 60),
          _sl('Saturation', 'saturation', -100, 100),
          _sl('Warmth', 'warmth', -60, 60, hint: 'Positive is warmer (orange), negative is cooler (blue).'),
        ];
      case 'sharpen':
        return [
          _sl('Amount', 'amount', 0, 3, step: 0.1),
          _sl('Radius', 'radius', 1, 6, hint: 'Small radius sharpens fine detail, large radius sharpens broad edges.'),
        ];
      case 'bw':
        return [
          _sl('Contrast', 'contrast', -60, 60),
          _switch('Pure black and white (threshold)', 'threshold'),
          if (params['threshold'] == true) _sl('Threshold', 'level', 20, 235),
        ];
      case 'upscale':
        return [
          Seg<double>(label: 'Enlarge by', value: num0(params, 'factor', 2), options: const [(2.0, '2×'), (3.0, '3×'), (4.0, '4×')], onChanged: (v) => _set('factor', v)),
          _sl('Sharpening', 'sharp', 0, 1.5, step: 0.1),
        ];
      case 'blurbg':
        return [
          Text('Tap or drag on the picture to move the sharp area.', style: body(13, color: C.muted)),
          const SizedBox(height: 8),
          _sl('Sharp area size', 'size', 0.1, 1, step: 0.02, disp: _pct),
          _sl('Blur strength', 'blur', 0.005, 0.08, step: 0.005, disp: (v) => '${(v * 1000).round() / 10}'),
          _sl('Soft edge', 'feather', 0.05, 1, step: 0.05, disp: _pct),
        ];
      case 'inpaint':
      case 'redact':
        return [
          if (op == 'redact') ...[
            Seg<String>(label: 'Hide with', value: params['style'], options: const [('blur', 'Blur'), ('pixelate', 'Pixelate'), ('cover', 'Black box')], onChanged: (v) => _set('style', v)),
            if (params['style'] != 'cover') _sl('Strength', 'strength', 0.01, 0.1, step: 0.005, disp: (v) => '${(v * 1000).round() / 10}'),
          ],
          SliderRow(label: 'Brush size', value: brushR, min: 0.01, max: 0.12, step: 0.005, display: '${(brushR * 200).round()}%', onChanged: (v) => setState(() => brushR = v)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(op == 'inpaint' ? 'Remove painted area' : 'Apply to painted area', kind: BtnKind.zest, onTap: strokes.isEmpty ? null : _commit),
            Btn('Undo', kind: BtnKind.line, onTap: _canUndo ? _undo : null),
            Btn('Clear paint', kind: BtnKind.line, onTap: strokes.isEmpty ? null : () {
              setState(() => strokes = []);
              _preview(now: true);
            }),
          ]),
          const SizedBox(height: 8),
          Text('Paint over the area with your finger. The result shows when you lift it. Press the button to lock it in, then paint the next spot.', style: body(12, color: C.muted)),
          const SizedBox(height: 12),
        ];
      case 'bgremove':
      case 'bgchange':
      case 'transparent':
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: C.pith, borderRadius: BorderRadius.circular(12)),
            child: Text(
              op == 'transparent'
                  ? (params['hasPick'] == true ? 'Tapped colour is now transparent. Tap another spot to change it.' : 'Tap the colour on the picture you want to remove. Until then the colour at the edges is used.')
                  : 'Colour-based remover (works best on plain backgrounds).',
              style: body(13, color: C.ink2),
            ),
          ),
          _sl('Tolerance', 'tolerance', 1, 100, hint: 'Raise until the background is gone, lower if your subject starts to disappear.'),
          if (op != 'transparent') _sl('Edge softness', 'softness', 0, 5),
          if (op == 'bgchange') ColorField(label: 'New background colour', value: params['fill'], onChanged: (v) => _set('fill', v)),
          if (op == 'transparent') _switch('Only the area connected to my tap', 'contiguous'),
        ];
      case 'border':
        return [
          _sl('Border width', 'width', 0, 0.15, step: 0.005, disp: (v) => '${(v * 200).round()}%'),
          ColorField(label: 'Border colour', value: params['color'], onChanged: (v) => _set('color', v)),
          _sl('Round the corners', 'radius', 0, 0.5, step: 0.01, disp: (v) => '${(v * 200).round()}%', hint: 'Rounded corners are saved as PNG so they stay transparent.'),
        ];
      case 'filter':
        return [
          Seg<String>(label: 'Look', value: params['preset'], options: [for (final f in kFilterNames) (f[0], f[1])], onChanged: (v) => _set('preset', v)),
          _sl('Strength', 'strength', 0.1, 1, step: 0.05, disp: _pct),
        ];
      case 'invert':
        return [_sl('Amount', 'strength', 0.1, 1, step: 0.05, disp: _pct, hint: '100% is a full negative.')];
      case 'blur':
        return [_sl('Blur strength', 'amount', 0.002, 0.1, step: 0.002, disp: (v) => '${(v * 1000).round() / 10}')];
      case 'sketch':
        return [
          _sl('Line softness', 'detail', 0.005, 0.06, step: 0.005, disp: (v) => '${(v * 1000).round() / 10}', hint: 'Smaller values give finer pencil lines.'),
          _sl('Darkness', 'darkness', 0.4, 2, step: 0.1, disp: _pct),
        ];
      case 'pixel':
        return [
          _sl('Pixel size', 'size', 0.005, 0.08, step: 0.005, disp: (v) => '${(v * 1000).round() / 10}'),
          _sl('Colours per channel', 'levels', 0, 16, disp: (v) => v < 2 ? 'All' : v.round().toString(), hint: 'Lower numbers give a retro, limited-colour look. 0 keeps every colour.'),
        ];
      case 'vignette':
        return [
          Seg<String>(label: 'Edges', value: params['tone'], options: const [('dark', 'Darken'), ('light', 'Lighten')], onChanged: (v) => _set('tone', v)),
          _sl('Strength', 'strength', 0.1, 1, step: 0.05, disp: _pct),
          _sl('Clear centre', 'size', 0.1, 1, step: 0.05, disp: _pct),
        ];
      case 'text':
        return [
          _textField('Your text', maxLines: 3, maxLength: 200),
          Seg<String>(label: 'Font', value: params['font'], options: const [('impact', 'Bold'), ('sans', 'Clean'), ('serif', 'Serif'), ('mono', 'Mono')], onChanged: (v) => _set('font', v)),
          _sl('Size', 'size', 0.02, 0.25, step: 0.005, disp: _pct),
          ColorField(label: 'Text colour', value: params['color'], onChanged: (v) => _set('color', v)),
          _posGrid(),
          _switch('Outline around letters', 'outline'),
          _switch('Dark box behind text', 'bar'),
        ];
      case 'pad':
        return [
          Seg<String>(label: 'Shape', value: params['ratio'], options: const [('1:1', '1:1'), ('4:5', '4:5'), ('9:16', '9:16'), ('16:9', '16:9')], onChanged: (v) => _set('ratio', v)),
          Seg<String>(label: 'Fill with', value: params['fill'], options: const [('blur', 'Blurred photo'), ('color', 'Colour'), ('transparent', 'Clear')], onChanged: (v) => _set('fill', v)),
          if (params['fill'] == 'color') ColorField(label: 'Colour', value: params['color'], onChanged: (v) => _set('color', v)),
          _sl('Extra space', 'margin', 0, 0.4, step: 0.02, disp: _pct),
        ];
    }
    return [];
  }

  List<Widget> _saveControls() {
    final alpha = needsAlpha(op, params);
    return [
      const Divider(height: 28),
      Seg<String>(label: 'Save as', value: fmtPick, options: const [('same', 'Same as original'), ('jpeg', 'JPG'), ('png', 'PNG'), ('webp', 'WebP')], onChanged: (v) => setState(() => fmtPick = v)),
      if (alpha) Text('This result has transparent areas, so JPG is switched to PNG automatically.', style: body(12, color: C.muted)),
      if (fmtPick != 'png') SliderRow(label: 'Quality', value: quality, min: 40, max: 100, display: '${quality.round()}%', onChanged: (v) => setState(() => quality = v.roundToDouble())),
    ];
  }
}

class _StrokePainter extends CustomPainter {
  final List<Stroke> strokes;
  _StrokePainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    final base = math.min(size.width, size.height);
    final p = Paint()
      ..color = const Color(0x8CFF4678)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final f = Paint()..color = const Color(0x8CFF4678);
    for (final s in strokes) {
      final r = math.max(1.0, s.r * base);
      if (s.pts.length == 1) {
        canvas.drawCircle(Offset(s.pts[0][0] * size.width, s.pts[0][1] * size.height), r, f);
      } else {
        p.strokeWidth = r * 2;
        final path = Path()..moveTo(s.pts[0][0] * size.width, s.pts[0][1] * size.height);
        for (var i = 1; i < s.pts.length; i++) {
          path.lineTo(s.pts[i][0] * size.width, s.pts[i][1] * size.height);
        }
        canvas.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

class _FocusPainter extends CustomPainter {
  final double cx, cy, size0;
  _FocusPainter(this.cx, this.cy, this.size0);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: Offset(cx * size.width, cy * size.height), width: size0 * size.width, height: size0 * size.height);
    canvas.drawOval(rect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawOval(rect.deflate(2), Paint()..color = C.pine..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _FocusPainter old) => true;
}
