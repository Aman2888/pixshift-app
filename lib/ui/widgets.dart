import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/files.dart';
import '../core/px.dart';
import '../theme.dart';

/// White rounded card, same look as the website's Panel.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: C.lineSoft)),
        child: child,
      );
}

class SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final double? step;
  final String? display, hint;
  final ValueChanged<double> onChanged;
  const SliderRow({super.key, required this.label, required this.value, required this.min, required this.max, this.step, this.display, this.hint, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final divisions = step == null ? null : ((max - min) / step!).round().clamp(1, 1000);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ', style: body(14, color: C.ink2)),
          TextSpan(text: display ?? _fmt(value), style: body(14, w: FontWeight.w800)),
        ])),
        Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
        if (hint != null) Text(hint!, style: body(12, color: C.muted)),
      ]),
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class Seg<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const Seg({super.key, required this.label, required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: body(14, color: C.ink2)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in options)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: value == o.$1 ? C.brand50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: value == o.$1 ? C.brand600 : C.line),
                  ),
                  child: Text(o.$2, style: body(14, color: value == o.$1 ? C.pine : C.ink2, w: FontWeight.w600)),
                ),
              ),
          ]),
        ]),
      );
}

const _swatches = ['#ffffff', '#000000', '#0d2b24', '#c8f23a', '#ff6a8b', '#ef4444', '#f59e0b', '#3b82f6', '#8b5cf6', '#14b8a6', '#f5f7ec', '#64748b'];

/// Colour picker: a row of swatches plus a hex box.
class ColorField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const ColorField({super.key, required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: body(14, color: C.ink2)),
        const SizedBox(height: 8),
        Row(children: [
          InkWell(
            onTap: () => _pick(context),
            child: Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(color: colorOf(value), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line, width: 2)),
            ),
          ),
          const SizedBox(width: 10),
          Text(value.toUpperCase(), style: body(14, w: FontWeight.w700)),
          const SizedBox(width: 8),
          TextButton(onPressed: () => _pick(context), child: const Text('Change')),
        ]),
      ]),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final ctrl = TextEditingController(text: value);
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: display(18)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in _swatches)
              InkWell(
                onTap: () => Navigator.pop(ctx, s),
                child: Container(width: 44, height: 44, decoration: BoxDecoration(color: colorOf(s), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line, width: 2))),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Hex colour, e.g. #1f5a46'), onSubmitted: (v) => Navigator.pop(ctx, v)),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: Btn('Use this colour', kind: BtnKind.zest, onTap: () => Navigator.pop(ctx, ctrl.text))),
        ]),
      ),
    );
    if (res != null && RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(res.trim())) {
      onChanged(res.trim().startsWith('#') ? res.trim().toLowerCase() : '#${res.trim().toLowerCase()}');
    }
  }
}

enum BtnKind { dark, line, zest }

class Btn extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final BtnKind kind;
  final IconData? icon;
  const Btn(this.text, {super.key, this.onTap, this.kind = BtnKind.dark, this.icon});
  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final bg = kind == BtnKind.dark ? C.pine : kind == BtnKind.zest ? C.zest : Colors.white;
    final fg = kind == BtnKind.dark ? Colors.white : C.pine;
    final border = kind == BtnKind.zest ? Border.all(color: C.pine, width: 2) : kind == BtnKind.line ? Border.all(color: C.line) : null;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: border),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
            Flexible(child: Text(text, style: body(14, color: fg, w: FontWeight.w800), textAlign: TextAlign.center)),
          ]),
        ),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String message;
  const ErrorBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.errBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFECDD3))),
        child: Text(message, style: body(14, color: C.err)),
      );
}

class InfoBox extends StatelessWidget {
  final String message;
  const InfoBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.brand50, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.brand100)),
        child: Text(message, style: body(14, color: C.brand600, w: FontWeight.w600)),
      );
}

/// Checkerboard behind transparent pictures (same as .checker in the website CSS).
class Checker extends StatelessWidget {
  final Widget child;
  const Checker({super.key, required this.child});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CheckerPainter(), child: child);
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()..color = C.checker;
    const s = 8.0;
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = 0.0; x < size.width; x += s) {
        if (((x / s).floor() + (y / s).floor()) % 2 == 0) canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Draws a dart:ui picture scaled to fit its box.
class UiImageView extends StatelessWidget {
  final ui.Image image;
  final double maxHeight;
  const UiImageView(this.image, {super.key, this.maxHeight = 360});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(aspectRatio: image.width / image.height, child: RawImage(image: image, fit: BoxFit.contain, filterQuality: FilterQuality.medium)),
      );
}

/// The "drop zone": big tappable area that opens the picker.
class PickZone extends StatelessWidget {
  final String icon, name, acceptLabel;
  final int count;
  final bool multiple;
  final VoidCallback onTap;
  const PickZone({super.key, required this.icon, required this.name, required this.acceptLabel, required this.count, required this.multiple, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final compact = count > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 14 : 32, horizontal: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: C.pine, width: 2)),
        child: compact
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_photo_alternate_outlined, color: C.pine),
                const SizedBox(width: 10),
                Text(multiple ? 'Add more images' : 'Choose a different image', style: body(15, w: FontWeight.w800)),
              ])
            : Column(children: [
                Text(icon, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 10),
                Text(multiple ? 'Tap to choose images' : 'Tap to choose an image', style: display(22), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(acceptLabel, style: body(13, color: C.muted)),
                const SizedBox(height: 4),
                Text('Stays on your phone. Nothing is uploaded.', style: body(12, color: C.brand500, w: FontWeight.w700)),
              ]),
      ),
    );
  }
}

/// Thumbnails of picked images with remove (and optional reorder) buttons.
class PicStrip extends StatelessWidget {
  final List<Pic> pics;
  final String? activeId;
  final ValueChanged<Pic>? onSelect;
  final ValueChanged<Pic> onRemove;
  final void Function(int index, int delta)? onMove;
  const PicStrip({super.key, required this.pics, this.activeId, this.onSelect, required this.onRemove, this.onMove});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: pics.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final p = pics[i];
            final active = p.id == activeId;
            return Stack(children: [
              GestureDetector(
                onTap: onSelect == null ? null : () => onSelect!(p),
                child: Container(
                  width: 84,
                  height: 84,
                  margin: const EdgeInsets.only(top: 6, right: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: active ? C.pine : C.line, width: active ? 3 : 1), color: Colors.white),
                  clipBehavior: Clip.antiAlias,
                  child: RawImage(image: p.image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => onRemove(p),
                  child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: C.pine, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)),
                ),
              ),
              if (onMove != null && pics.length > 1)
                Positioned(
                  left: 4,
                  bottom: 10,
                  child: Row(children: [
                    if (i > 0) _arrow(Icons.chevron_left, () => onMove!(i, -1)),
                    if (i < pics.length - 1) _arrow(Icons.chevron_right, () => onMove!(i, 1)),
                  ]),
                ),
            ]);
          },
        ),
      );

  Widget _arrow(IconData ic, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(margin: const EdgeInsets.only(right: 4), width: 26, height: 26, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle, border: Border.all(color: C.pine)), child: Icon(ic, size: 18, color: C.pine)),
      );
}

/// Save / Gallery / Share row for one finished file.
class OutputBar extends StatelessWidget {
  final Uint8List bytes;
  final String name;
  final String mime;
  final bool image;
  const OutputBar({super.key, required this.bytes, required this.name, required this.mime, this.image = true});

  void _toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        Btn('Save', icon: Icons.download_rounded, kind: BtnKind.zest, onTap: () async {
          try {
            final ok = await saveToDevice(bytes, name);
            if (context.mounted && ok) _toast(context, 'Saved $name');
          } catch (e) {
            if (context.mounted) _toast(context, 'Could not save: $e');
          }
        }),
        if (image)
          Btn('Gallery', icon: Icons.photo_library_outlined, kind: BtnKind.line, onTap: () async {
            try {
              await saveToGallery(bytes, name);
              if (context.mounted) _toast(context, 'Saved to your gallery');
            } catch (e) {
              if (context.mounted) _toast(context, 'Could not save to gallery: $e');
            }
          }),
        Btn('Share', icon: Icons.ios_share, kind: BtnKind.line, onTap: () => shareBytes(bytes, name, mime)),
      ]);
}

/// Number input that reports null while empty.
class NumField extends StatefulWidget {
  final String label;
  final double? value;
  final String? suffix;
  final ValueChanged<double?> onChanged;
  const NumField({super.key, required this.label, required this.value, required this.onChanged, this.suffix});
  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController c;
  @override
  void initState() {
    super.initState();
    c = TextEditingController(text: _s(widget.value));
  }

  String _s(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void didUpdateWidget(covariant NumField old) {
    super.didUpdateWidget(old);
    final cur = double.tryParse(c.text);
    if (widget.value != cur && !(widget.value == null && c.text.isEmpty)) {
      c.text = _s(widget.value);
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: body(14, color: C.ink2)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: widget.suffix),
            onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : double.tryParse(v)),
          ),
        ]),
      );
}
