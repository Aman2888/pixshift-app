import 'package:flutter/material.dart';
import '../data/tool_model.dart';
import '../data/tools_data.dart';
import '../engines/base64_engine.dart';
import '../engines/calc_engine.dart';
import '../engines/collage_engine.dart';
import '../engines/color_engine.dart';
import '../engines/combine_engine.dart';
import '../engines/crop_engine.dart';
import '../engines/favicon_engine.dart';
import '../engines/meme_engine.dart';
import '../engines/pdf_engine.dart';
import '../engines/split_engine.dart';
import '../engines/editor_engine.dart';
import '../engines/image_engine.dart';
import '../theme.dart';
import '../ui/widgets.dart';

/// All 12 engines are built.
const Set<String> kReadyEngines = {'image', 'editor', 'crop', 'color', 'calc', 'base64', 'pdf', 'combine', 'split', 'favicon', 'collage', 'meme'};

Tool? toolBySlug(String s) {
  for (final t in kTools) {
    if (t.slug == s) return t;
  }
  return null;
}

Widget buildEngine(Tool t) {
  switch (t.engine) {
    case 'image':
      return ImageEngine(key: ValueKey(t.slug), tool: t);
    case 'editor':
      return EditorEngine(key: ValueKey(t.slug), tool: t);
    case 'crop':
      return CropEngine(key: ValueKey(t.slug), tool: t);
    case 'color':
      return ColorEngine(key: ValueKey(t.slug), tool: t);
    case 'calc':
      return CalcEngine(key: ValueKey(t.slug), tool: t);
    case 'base64':
      return Base64Engine(key: ValueKey(t.slug), tool: t);
    case 'pdf':
      return PdfEngine(key: ValueKey(t.slug), tool: t);
    case 'combine':
      return CombineEngine(key: ValueKey(t.slug), tool: t);
    case 'split':
      return SplitEngine(key: ValueKey(t.slug), tool: t);
    case 'favicon':
      return FaviconEngine(key: ValueKey(t.slug), tool: t);
    case 'collage':
      return CollageEngine(key: ValueKey(t.slug), tool: t);
    case 'meme':
      return MemeEngine(key: ValueKey(t.slug), tool: t);
  }
  return Panel(
    child: Column(children: [
      Text(t.icon, style: const TextStyle(fontSize: 40)),
      const SizedBox(height: 8),
      Text('Coming in the next update', style: display(20)),
      const SizedBox(height: 4),
      Text('This tool is being added to the app.', style: body(14, color: C.muted)),
    ]),
  );
}

class ToolScreen extends StatelessWidget {
  final Tool tool;
  const ToolScreen({super.key, required this.tool});
  @override
  Widget build(BuildContext context) {
    final related = tool.related.map(toolBySlug).whereType<Tool>().toList();
    return Scaffold(
      appBar: AppBar(title: Text(tool.name, style: display(18))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          Text(tool.h1, style: display(28)),
          const SizedBox(height: 6),
          Text(tool.short, style: body(15, color: C.ink2)),
          const SizedBox(height: 14),
          if (tool.note != null) InfoBox(tool.note!),
          buildEngine(tool),
          const SizedBox(height: 24),
          Text('Quick answer', style: display(20)),
          const SizedBox(height: 6),
          Text(tool.quickAnswer, style: body(14, color: C.ink2, h: 1.4)),
          const SizedBox(height: 18),
          Text('How it works', style: display(20)),
          const SizedBox(height: 6),
          for (var i = 0; i < tool.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 24, height: 24, alignment: Alignment.center, decoration: const BoxDecoration(color: C.zest, shape: BoxShape.circle), child: Text('${i + 1}', style: body(12, w: FontWeight.w800))),
                const SizedBox(width: 10),
                Expanded(child: Text(tool.steps[i], style: body(14, color: C.ink2, h: 1.35))),
              ]),
            ),
          const SizedBox(height: 14),
          Text('FAQ', style: display(20)),
          for (final f in tool.faqs)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(f.q, style: body(14, w: FontWeight.w800)), childrenPadding: const EdgeInsets.only(bottom: 8), expandedAlignment: Alignment.centerLeft, children: [Text(f.a, style: body(14, color: C.ink2, h: 1.4))]),
            ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Related tools', style: display(20)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in related)
                ActionChip(label: Text('${r.icon} ${r.name}'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ToolScreen(tool: r)))),
            ]),
          ],
        ]),
      ),
    );
  }
}
