import 'package:flutter/material.dart';
import '../data/tools_data.dart';
import '../theme.dart';
import 'tools_hub.dart';

/// Bottom-navigation tab: all categories as a grid. Tap one to open its tools.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final groups = kGroupLabels.entries.toList();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Text('Categories', style: display(30)),
        const SizedBox(height: 4),
        Text('Pick a category to see its tools.', style: body(14, color: C.muted)),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.0,
          children: [
            for (final g in groups)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryScreen(groupKey: g.key))),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.lineSoft)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: C.brand50, borderRadius: BorderRadius.circular(14)),
                      child: Text(kTools.firstWhere((t) => t.group == g.key).icon, style: const TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(height: 10),
                    Text(g.value[0], maxLines: 2, overflow: TextOverflow.ellipsis, style: display(16)),
                    const SizedBox(height: 2),
                    Text('${kTools.where((t) => t.group == g.key).length} tools', style: body(12, color: C.brand500, w: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Expanded(child: Text(g.value[1], maxLines: 3, overflow: TextOverflow.ellipsis, style: body(12, color: C.muted))),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

/// The tools of one category.
class CategoryScreen extends StatelessWidget {
  final String groupKey;
  const CategoryScreen({super.key, required this.groupKey});
  @override
  Widget build(BuildContext context) {
    final label = kGroupLabels[groupKey]!;
    final list = kTools.where((t) => t.group == groupKey).toList();
    return Scaffold(
      appBar: AppBar(title: Text(label[0], style: display(18))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Text(label[1], style: body(14, color: C.ink2, h: 1.4)),
          const SizedBox(height: 4),
          Text('${list.length} tools', style: body(13, color: C.brand500, w: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final t in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: ToolTile(t)),
        ]),
      ),
    );
  }
}