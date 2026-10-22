// Image to Base64 and Base64 to image. Port of components/Base64Tool.tsx.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/files.dart';
import '../core/px.dart';
import '../data/tool_model.dart';
import '../theme.dart';
import '../ui/widgets.dart';

String _mimeOf(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.svg')) return 'image/svg+xml';
  if (n.endsWith('.bmp')) return 'image/bmp';
  if (n.endsWith('.avif')) return 'image/avif';
  return 'image/jpeg';
}

const _ext = {'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif', 'image/webp': 'webp', 'image/svg+xml': 'svg', 'image/bmp': 'bmp', 'image/avif': 'avif'};

String _sniff(Uint8List b) {
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
  if (b.length > 3 && b[0] == 0xff && b[1] == 0xd8) return 'image/jpeg';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
  if (b.length > 1 && b[0] == 0x42 && b[1] == 0x4d) return 'image/bmp';
  return 'image/png';
}

class Base64Engine extends StatefulWidget {
  final Tool tool;
  const Base64Engine({super.key, required this.tool});
  @override
  State<Base64Engine> createState() => _Base64State();
}

class _Base64State extends State<Base64Engine> {
  bool get toMode => widget.tool.mode != 'from';
  String error = '', dataUrl = '', copied = '';
  Pic? pic;
  final ctrl = TextEditingController();
  Uint8List? decoded;
  ui.Image? decodedImg;
  String decodedMime = 'image/png';

  Future<void> _pick() async {
    try {
      final got = await _pickAny();
      if (got == null) return;
      setState(() {
        error = '';
        pic = got.$1;
        dataUrl = 'data:${got.$2};base64,${base64Encode(got.$1.bytes)}';
      });
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<(Pic, String)?> _pickAny() async {
    final got = await pickPics(accept: widget.tool.accept, multiple: false);
    if (got.isEmpty) return null;
    return (got.first, _mimeOf(got.first.name));
  }

  Future<void> _decode(String text) async {
    final t = text.trim().replaceAll(RegExp('^["\']|["\']\$'), '');
    if (t.isEmpty) {
      setState(() {
        decoded = null;
        decodedImg = null;
        error = '';
      });
      return;
    }
    try {
      var raw = t;
      String? mime;
      final m = RegExp(r'^data:([^;,]+)?(;base64)?,(.*)$', dotAll: true).firstMatch(t);
      if (m != null) {
        mime = m.group(1);
        raw = m.group(3)!;
      }
      raw = raw.replaceAll(RegExp(r'\s'), '');
      final bytes = base64Decode(base64.normalize(raw));
      final img = await decodeImageSafe(bytes);
      setState(() {
        decoded = bytes;
        decodedImg = img;
        decodedMime = mime ?? _sniff(bytes);
        error = '';
      });
    } catch (_) {
      setState(() {
        decoded = null;
        decodedImg = null;
        error = 'That text is not a valid Base64 image.';
      });
    }
  }

  Future<ui.Image> decodeImageSafe(Uint8List b) => decodeBytes(b);

  Future<void> _copy(String label, String text) async {
    await copyText(text);
    setState(() => copied = label);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && copied == label) setState(() => copied = '');
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (toMode) {
      final raw = dataUrl.contains(',') ? dataUrl.split(',').last : '';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PickZone(icon: widget.tool.icon, name: widget.tool.name, acceptLabel: widget.tool.acceptLabel, count: pic == null ? 0 : 1, multiple: false, onTap: _pick),
        const SizedBox(height: 12),
        if (error.isNotEmpty) ErrorBox(error),
        if (pic != null)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${pic!.name} · ${formatBytes(pic!.bytes.length)} → ${formatBytes(dataUrl.length)} of text', style: body(13, color: C.muted)),
              const SizedBox(height: 10),
              for (final r in [
                ['Data URI', dataUrl],
                ['Base64 only', raw],
                ['HTML', '<img src="$dataUrl" alt="">'],
                ['CSS', 'background-image: url("$dataUrl");'],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r[0], style: body(14, w: FontWeight.w800))),
                      TextButton(onPressed: () => _copy(r[0], r[1]), child: Text(copied == r[0] ? 'Copied!' : 'Copy')),
                    ]),
                    Container(
                      height: 64,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: C.pith, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.lineSoft)),
                      child: Text(r[1], maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ]),
                ),
            ]),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Paste your Base64 text', style: display(18)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, minLines: 5, maxLines: 8, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), decoration: const InputDecoration(hintText: 'data:image/png;base64,iVBOR… or just the Base64'), onChanged: _decode),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            Btn('Paste from clipboard', kind: BtnKind.line, onTap: () async {
              final d = await Clipboard2.paste();
              if (d != null) {
                ctrl.text = d;
                _decode(d);
              }
            }),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (error.isNotEmpty) ErrorBox(error),
      if (decodedImg != null && decoded != null)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checker(child: Padding(padding: const EdgeInsets.all(8), child: Center(child: UiImageView(decodedImg!)))),
            const SizedBox(height: 8),
            Text('${decodedImg!.width}×${decodedImg!.height} · ${formatBytes(decoded!.length)}', style: body(13, color: C.muted)),
            const SizedBox(height: 8),
            OutputBar(bytes: decoded!, name: 'pixshift-image.${_ext[decodedMime] ?? 'png'}', mime: decodedMime),
          ]),
        ),
    ]);
  }
}

class Clipboard2 {
  static Future<String?> paste() async {
    final d = await Clipboard.getData('text/plain');
    return d?.text;
  }
}
