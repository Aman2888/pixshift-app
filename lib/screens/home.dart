import 'package:flutter/material.dart';
import '../data/tool_model.dart';
import '../data/tools_data.dart';
import '../theme.dart';
import '../ui/logo.dart';
import 'tool_screen.dart';
import 'tools_hub.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onSeeAll;
  const HomeScreen({super.key, required this.onSeeAll});
  static const popular = ['image-compressor', 'image-resizer', 'background-remover', 'passport-size-photo-maker', 'image-cropper', 'image-to-pdf', 'compress-image-to-100kb', 'png-to-jpg'];
  @override
  Widget build(BuildContext context) {
    final pop = popular.map(toolBySlug).whereType<Tool>().toList();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: C.pine,
            gradient: const RadialGradient(center: Alignment(1.0, -1.1), radius: 1.2, colors: [Color(0x66C8F23A), C.pine]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const PixLogo(size: 38),
              const SizedBox(width: 10),
              Text('PixShift', style: display(22, color: Colors.white)),
            ]),
            const SizedBox(height: 10),
            Text('Free image tools. Private by design.', style: display(32, color: Colors.white)),
            const SizedBox(height: 10),
            Text('Compress, resize, convert and edit photos. Everything runs on your phone. Nothing is uploaded.', style: body(14, color: Colors.white70, h: 1.35)),
            const SizedBox(height: 16),
            InkWell(
              onTap: onSeeAll,
              borderRadius: BorderRadius.circular(999),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12), decoration: BoxDecoration(color: C.zest, borderRadius: BorderRadius.circular(999)), child: Text('Browse all tools', style: body(15, w: FontWeight.w800))),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        Text('Popular', style: display(22)),
        const SizedBox(height: 10),
        for (final t in pop) Padding(padding: const EdgeInsets.only(bottom: 8), child: ToolTile(t)),
      ]),
    );
  }
}