class Preset {
  final String id;
  final String label;
  final int w;
  final int h;
  const Preset(this.id, this.label, this.w, this.h);
}

class Faq {
  final String q;
  final String a;
  const Faq(this.q, this.a);
}

class Tool {
  final String slug, name, icon, group, engine, kind, output;
  final String? op, calc, mode, platform, note;
  final String short, color, accept, acceptLabel, h1, quickAnswer;
  final int? targetKb, fixedW, fixedH;
  final List<String> steps;
  final List<Preset> presets;
  final List<Faq> faqs;
  final List<String> related;

  const Tool({
    required this.slug,
    required this.name,
    required this.icon,
    required this.group,
    required this.engine,
    required this.kind,
    required this.output,
    this.op,
    this.calc,
    this.mode,
    required this.short,
    required this.color,
    required this.accept,
    required this.acceptLabel,
    this.platform,
    this.targetKb,
    this.fixedW,
    this.fixedH,
    this.note,
    required this.h1,
    required this.quickAnswer,
    required this.steps,
    required this.presets,
    required this.faqs,
    required this.related,
  });

  
}

/// Tiny wrapper so the data layer does not depend on Flutter.
class Color0 {
  final String hex;
  const Color0(this.hex);
  int get argb {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return int.tryParse(h, radix: 16) ?? 0xFF3F7D5C;
  }
}
