// Compress / resize / convert / social presets / target size. Port of components/ImageTool.tsx.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/files.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

class _Item {
  final Pic pic;
  String status = 'wait'; // wait | work | done | error
  Uint8List? out;
  String outName = '';
  int outW = 0, outH = 0;
  String error = '';
  _Item(this.pic);
}

class ImageEngine extends StatefulWidget {
  final Tool tool;
  const ImageEngine({super.key, required this.tool});
  @override
  State<ImageEngine> createState() => _ImageEngineState();
}

class _ImageEngineState extends State<ImageEngine> {
  final List<_Item> items = [];
  late double quality = widget.tool.kind == 'compress' ? 75 : 90;
  String mode = 'pixels';
  double? width, height;
  double percent = 50;
  bool lock = true;
  late String presetId = widget.tool.presets.isNotEmpty ? widget.tool.presets.first.id : '';
  FitMode fit = FitMode.fill;
  String bg = '#ffffff';
  String error = '';
  Timer? _debounce;
  int _run = 0;

  Tool get tool => widget.tool;
  bool get frameMode => tool.kind == 'social' || tool.kind == 'fixed';
  bool get showQuality =>
      tool.kind == 'compress' || frameMode || (tool.kind == 'convert' && tool.output != 'png') || (tool.kind == 'resize' && tool.output != 'png');

  Preset? get preset {
    if (tool.kind == 'fixed' && tool.fixedW != null) return Preset('fixed', '', tool.fixedW!, tool.fixedH!);
    for (final p in tool.presets) {
      if (p.id == presetId) return p;
    }
    return null;
  }

  Fmt _format(Pic p) => tool.output == 'same' ? formatFromName(p.name) : (fmtFromString(tool.output) ?? Fmt.jpeg);

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: tool.accept);
      if (got.isEmpty) return;
      setState(() {
        error = '';
        items.addAll(got.map(_Item.new));
        if (tool.kind == 'resize' && width == null && height == null) {
          width = got.first.w.toDouble();
          height = got.first.h.toDouble();
        }
      });
      _schedule(now: true);
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _schedule({bool now = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: now ? 10 : 500), _runAll);
  }

  Future<void> _runAll() async {
    final token = ++_run;
    for (final it in List<_Item>.from(items)) {
      if (token != _run || !mounted) return;
      setState(() => it.status = 'work');
      try {
        await _runOne(it);
        it.status = 'done';
      } catch (e) {
        it.status = 'error';
        it.error = e.toString().replaceFirst('Exception: ', '');
      }
      if (token != _run || !mounted) return;
      setState(() {});
    }
  }

  Future<void> _runOne(_Item it) async {
    final p = it.pic;
    final fmt = _format(p);
    if (tool.kind == 'target' && tool.targetKb != null) {
      final r = await fitUnder(p.image, (tool.targetKb! * 1024 * 0.99).floor(), format: Fmt.jpeg, background: bg);
      it.out = r.bytes;
      it.outW = r.width;
      it.outH = r.height;
      it.outName = '${baseName(p.name)}-${tool.targetKb}kb.jpg';
      return;
    }
    double? w, h;
    var fitMode = FitMode.stretch;
    if (tool.kind == 'resize') {
      if (mode == 'percent') {
        w = p.w * percent / 100;
        h = p.h * percent / 100;
      } else if (width != null && height != null) {
        if (lock) {
          w = width;
          h = p.h * width! / p.w;
        } else {
          w = width;
          h = height;
        }
      }
    } else if (frameMode && preset != null) {
      w = preset!.w.toDouble();
      h = preset!.h.toDouble();
      fitMode = fit;
    }
    final res = await processImage(p.image,
        format: fmt, quality: (fmt == Fmt.png && tool.kind != 'compress') ? 100 : quality.round(), width: w?.round(), height: h?.round(), fit: fitMode, background: bg);
    final suffix = frameMode && preset != null ? '-${preset!.w}x${preset!.h}' : (tool.kind == 'resize' ? '-${res.width}x${res.height}' : '-pixshift');
    it.out = res.bytes;
    it.outW = res.width;
    it.outH = res.height;
    it.outName = '${baseName(p.name)}$suffix.${kExt[fmt]}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _run++;
    super.dispose();
  }

  void _remove(_Item it) {
    setState(() => items.remove(it));
  }

  @override
  Widget build(BuildContext context) {
    final done = items.where((i) => i.status == 'done' && i.out != null).toList();
    final before = done.fold<int>(0, (s, i) => s + i.pic.bytes.length);
    final after = done.fold<int>(0, (s, i) => s + i.out!.length);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PickZone(icon: tool.icon, name: tool.name, acceptLabel: tool.acceptLabel, count: items.length, multiple: true, onTap: _pick),
      const SizedBox(height: 12),
      if (error.isNotEmpty) ErrorBox(error),
      if (tool.kind == 'target')
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.zest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.pine, width: 2)),
          child: Text('🎯 Target: under ${tool.targetKb} KB. PixShift finds the best quality that fits. No settings needed.', style: body(14, w: FontWeight.w700)),
        ),
      if (showQuality || frameMode || tool.kind == 'resize') Panel(child: _settings()),
      const SizedBox(height: 12),
      if (done.isNotEmpty && before > 0)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: C.brand50, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: Text('${formatBytes(before)} → ${formatBytes(after)}', style: body(16, w: FontWeight.w800))),
            if ((tool.kind == 'compress' || tool.kind == 'target') && after < before)
              Text('−${((1 - after / before) * 100).round()}%', style: display(20, color: C.brand600)),
          ]),
        ),
      for (final it in items) _card(it),
      if (done.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Btn('Save all as ZIP', icon: Icons.folder_zip_outlined, kind: BtnKind.dark, onTap: () async {
            final zip = zipFiles([for (final d in done) MapEntry(d.outName, d.out!)]);
            await saveToDevice(zip, 'pixshift-images.zip');
          }),
        ),
    ]);
  }

  Widget _settings() {
    final kids = <Widget>[];
    if (tool.kind == 'social' && tool.presets.length > 1) {
      kids.add(Seg<String>(label: '${tool.platform} size', value: presetId, options: [for (final p in tool.presets) (p.id, p.label)], onChanged: (v) {
        setState(() => presetId = v);
        _schedule();
      }));
    } else if (frameMode && preset != null && preset!.label.isNotEmpty) {
      kids.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('${preset!.label}', style: body(14, w: FontWeight.w700))));
    }
    if (frameMode) {
      kids.add(Seg<FitMode>(label: 'How to fit', value: fit, options: const [(FitMode.fill, 'Fill and crop'), (FitMode.fit, 'Fit inside')], onChanged: (v) {
        setState(() => fit = v);
        _schedule();
      }));
      if (fit == FitMode.fit) {
        kids.add(ColorField(label: 'Background colour', value: bg, onChanged: (v) {
          setState(() => bg = v);
          _schedule();
        }));
      }
    }
    if (tool.kind == 'resize') {
      kids.add(Seg<String>(label: 'Resize by', value: mode, options: const [('pixels', 'Pixels'), ('percent', 'Percent')], onChanged: (v) {
        setState(() => mode = v);
        _schedule();
      }));
      if (mode == 'percent') {
        kids.add(SliderRow(label: 'Scale', value: percent, min: 5, max: 300, display: '${percent.round()}%', onChanged: (v) {
          setState(() => percent = v.roundToDouble());
          _schedule();
        }));
      } else {
        final first = items.isNotEmpty ? items.first.pic : null;
        kids.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: NumField(label: 'Width', suffix: 'px', value: width, onChanged: (v) {
            setState(() {
              width = v;
              if (lock && v != null && first != null) height = (v * first.h / first.w).roundToDouble();
            });
            _schedule();
          })),
          const SizedBox(width: 12),
          Expanded(
              child: NumField(label: 'Height', suffix: 'px', value: height, onChanged: (v) {
            setState(() {
              height = v;
              if (lock && v != null && first != null) width = (v * first.w / first.h).roundToDouble();
            });
            _schedule();
          })),
        ]));
        kids.add(Row(children: [
          Switch(value: lock, activeColor: C.brand600, onChanged: (v) => setState(() => lock = v)),
          Text('Lock aspect ratio', style: body(14)),
        ]));
      }
    }
    if (showQuality) {
      kids.add(SliderRow(
          label: 'Quality',
          value: quality,
          min: 1,
          max: 100,
          display: '${quality.round()}%',
          hint: 'Lower quality means a smaller file. PNG output uses fewer colours below 100%.',
          onChanged: (v) {
            setState(() => quality = v.roundToDouble());
            _schedule();
          }));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids);
  }

  Widget _card(_Item it) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.lineSoft)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
            clipBehavior: Clip.antiAlias,
            child: RawImage(image: it.pic.image, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.pic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, w: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${it.pic.w}×${it.pic.h} · ${formatBytes(it.pic.bytes.length)}', style: body(12, color: C.muted)),
              if (it.status == 'done') Text('→ ${it.outW}×${it.outH} · ${formatBytes(it.out!.length)}', style: body(13, color: C.brand600, w: FontWeight.w800)),
              if (it.status == 'work') Text('Working…', style: body(13, color: C.muted)),
              if (it.status == 'error') Text(it.error, style: body(12, color: C.err)),
            ]),
          ),
          IconButton(onPressed: () => _remove(it), icon: const Icon(Icons.close)),
        ]),
        if (it.status == 'done') ...[
          const SizedBox(height: 10),
          OutputBar(bytes: it.out!, name: it.outName, mime: it.outName.endsWith('.png') ? 'image/png' : it.outName.endsWith('.webp') ? 'image/webp' : it.outName.endsWith('.avif') ? 'image/avif' : 'image/jpeg'),
        ],
      ]),
    );
  }
}
