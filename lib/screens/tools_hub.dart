import 'package:flutter/material.dart';
import '../data/tool_model.dart';
import '../data/tools_data.dart';
import '../theme.dart';
import 'tool_screen.dart';

Color toolColor(Tool t) {
  final h = t.color.replaceAll('#', '');
  return Color(int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16) ?? 0xFF3F7D5C);
}

class ToolTile extends StatelessWidget {
  final Tool tool;
  const ToolTile(this.tool, {super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ToolScreen(tool: tool))),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.lineSoft)),
          child: Row(children: [
            Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: toolColor(tool).withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)), child: Text(tool.icon, style: const TextStyle(fontSize: 24))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tool.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(15, w: FontWeight.w800)),
                Text(tool.short, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12, color: C.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: C.muted),
          ]),
        ),
      );
}

class ToolsHub extends StatefulWidget {
  const ToolsHub({super.key});
  @override
  State<ToolsHub> createState() => _ToolsHubState();
}

class _ToolsHubState extends State<ToolsHub> {
  String q = '';
  String group = 'all';
  @override
  Widget build(BuildContext context) {
    final ql = q.trim().toLowerCase();
    final list = kTools.where((t) {
      if (group != 'all' && t.group != group) return false;
      if (ql.isEmpty) return true;
      return t.name.toLowerCase().contains(ql) || t.short.toLowerCase().contains(ql) || t.slug.contains(ql.replaceAll(' ', '-'));
    }).toList();
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All tools', style: display(30)),
            const SizedBox(height: 10),
            TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tools, e.g. compress, passport'), onChanged: (v) => setState(() => q = v)),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final g in ['all', ...kGroupLabels.keys])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(g == 'all' ? 'All' : kGroupLabels[g]![0]),
                  selected: group == g,
                  selectedColor: C.zest,
                  side: BorderSide(color: group == g ? C.pine : C.line),
                  onSelected: (_) => setState(() => group = g),
                ),
              ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('No tools match “$q”.', style: body(15, color: C.muted)))
              : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => ToolTile(list[i])),
        ),
      ]),
    );
  }
}
