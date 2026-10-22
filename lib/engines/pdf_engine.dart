// Images to PDF. Port of components/PdfTool.tsx.
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/codec.dart';
import '../core/files.dart';
import '../core/ico_pdf.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

class PdfEngine extends StatefulWidget {
  final Tool tool;
  const PdfEngine({super.key, required this.tool});
  @override
  State<PdfEngine> createState() => _PdfEngineState();
}

class _PdfEngineState extends State<PdfEngine> {
  final List<Pic> pics = [];
  String size = 'a4', orient = 'auto';
  double margin = 18, quality = 85;
  bool busy = false;
  String error = '', message = '';
  Uint8List? pdf;

  Future<void> _pick() async {
    try {
      final got = await pickPics(accept: widget.tool.accept);
      setState(() {
        pics.addAll(got);
        error = '';
        pdf = null;
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _make() async {
    setState(() {
      busy = true;
      error = '';
      message = '';
      pdf = null;
    });
    try {
      final pages = <PdfPage>[];
      for (final p in pics) {
        final s = math.min(1.0, 3200 / math.max(p.w, p.h));
        final w = math.max(1, (p.w * s).round()), h = math.max(1, (p.h * s).round());
        final scaled = await scaleTo(p.image, w, h);
        final jpeg = await encodeImage(scaled, Fmt.jpeg, quality.round());
        final pl = placeOnPage(w, h, size, orient, margin);
        pages.add(PdfPage(jpeg, w, h, pl.pageW, pl.pageH, pl.x, pl.y, pl.dw, pl.dh));
      }
      final bytes = buildPdf(pages);
      setState(() {
        pdf = bytes;
        message = '${pages.length} page${pages.length > 1 ? 's' : ''} · ${formatBytes(bytes.length)}';
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
        Text('Pages, in order', style: body(14, w: FontWeight.w800)),
        const SizedBox(height: 6),
        PicStrip(
          pics: pics,
          onRemove: (p) => setState(() {
            pics.remove(p);
            pdf = null;
          }),
          onMove: (i, d) => setState(() {
            final p = pics.removeAt(i);
            pics.insert(i + d, p);
            pdf = null;
          }),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Seg<String>(label: 'Page size', value: size, options: const [('a4', 'A4'), ('letter', 'US Letter'), ('fit', 'Fit each image')], onChanged: (v) => setState(() => size = v)),
            if (size != 'fit') Seg<String>(label: 'Orientation', value: orient, options: const [('auto', 'Auto'), ('portrait', 'Portrait'), ('landscape', 'Landscape')], onChanged: (v) => setState(() => orient = v)),
            Seg<double>(label: 'Margin', value: margin, options: const [(0.0, 'None'), (18.0, 'Small'), (36.0, 'Large')], onChanged: (v) => setState(() => margin = v)),
            SliderRow(label: 'Picture quality', value: quality, min: 40, max: 100, display: '${quality.round()}%', hint: 'Lower quality makes a smaller PDF.', onChanged: (v) => setState(() => quality = v.roundToDouble())),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Btn(busy ? 'Building PDF…' : 'Create PDF (${pics.length} page${pics.length > 1 ? 's' : ''})', icon: Icons.picture_as_pdf_outlined, onTap: busy ? null : _make),
          Btn('Clear', kind: BtnKind.line, onTap: () => setState(() {
                pics.clear();
                pdf = null;
              })),
        ]),
        if (pdf != null) ...[
          const SizedBox(height: 12),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('pixshift-images.pdf', style: body(14, w: FontWeight.w800)),
            Text(message, style: body(12, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: pdf!, name: 'pixshift-images.pdf', mime: 'application/pdf', image: false),
          ])),
        ],
      ],
    ]);
  }
}
