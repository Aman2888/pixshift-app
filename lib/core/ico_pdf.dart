// Tiny writers for .ico and .pdf (ports of lib/ico.ts and lib/pdf.ts). No libraries needed.
import 'dart:convert';
import 'dart:typed_data';

class IcoImage {
  final int size;
  final Uint8List png;
  IcoImage(this.size, this.png);
}

Uint8List buildIco(List<IcoImage> images) {
  final head = 6 + images.length * 16;
  final total = images.fold<int>(head, (t, i) => t + i.png.length);
  final out = Uint8List(total);
  final v = ByteData.view(out.buffer);
  v.setUint16(0, 0, Endian.little);
  v.setUint16(2, 1, Endian.little);
  v.setUint16(4, images.length, Endian.little);
  var at = head;
  for (var i = 0; i < images.length; i++) {
    final im = images[i];
    final o = 6 + i * 16;
    out[o] = im.size >= 256 ? 0 : im.size;
    out[o + 1] = im.size >= 256 ? 0 : im.size;
    out[o + 2] = 0;
    out[o + 3] = 0;
    v.setUint16(o + 4, 1, Endian.little);
    v.setUint16(o + 6, 32, Endian.little);
    v.setUint32(o + 8, im.png.length, Endian.little);
    v.setUint32(o + 12, at, Endian.little);
    out.setRange(at, at + im.png.length, im.png);
    at += im.png.length;
  }
  return out;
}

class PdfPage {
  final Uint8List jpeg;
  final int w, h;
  final double pageW, pageH, x, y, dw, dh;
  PdfPage(this.jpeg, this.w, this.h, this.pageW, this.pageH, this.x, this.y, this.dw, this.dh);
}

const Map<String, List<double>> kPageSizes = {
  'a4': [595.28, 841.89],
  'letter': [612, 792],
};

String _num(double n) {
  final r = (n * 100).round() / 100;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

Uint8List buildPdf(List<PdfPage> pages) {
  final chunks = <Uint8List>[];
  final offsets = <int, int>{};
  var size = 0;
  void push(Object b) {
    final u = b is String ? Uint8List.fromList(latin1.encode(b)) : b as Uint8List;
    chunks.add(u);
    size += u.length;
  }

  void obj(int id, void Function() body) {
    offsets[id] = size;
    push('$id 0 obj\n');
    body();
    push('\nendobj\n');
  }

  push('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  int pageId(int i) => 3 + i * 3;
  obj(1, () => push('<< /Type /Catalog /Pages 2 0 R >>'));
  obj(2, () => push('<< /Type /Pages /Count ${pages.length} /Kids [${List.generate(pages.length, (i) => '${pageId(i)} 0 R').join(' ')}] >>'));
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    final id = pageId(i);
    obj(id, () => push('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_num(p.pageW)} ${_num(p.pageH)}] /Resources << /XObject << /Im0 ${id + 2} 0 R >> >> /Contents ${id + 1} 0 R >>'));
    final y = p.pageH - p.y - p.dh;
    final content = 'q ${_num(p.dw)} 0 0 ${_num(p.dh)} ${_num(p.x)} ${_num(y)} cm /Im0 Do Q';
    obj(id + 1, () => push('<< /Length ${content.length} >>\nstream\n$content\nendstream'));
    obj(id + 2, () {
      push('<< /Type /XObject /Subtype /Image /Width ${p.w} /Height ${p.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n');
      push(p.jpeg);
      push('\nendstream');
    });
  }
  final count = 3 + pages.length * 3;
  final xref = size;
  push('xref\n0 $count\n0000000000 65535 f \n');
  for (var i = 1; i < count; i++) {
    push('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  push('trailer\n<< /Size $count /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  final out = Uint8List(size);
  var at = 0;
  for (final c in chunks) {
    out.setRange(at, at + c.length, c);
    at += c.length;
  }
  return out;
}

class Placement {
  final double pageW, pageH, x, y, dw, dh;
  Placement(this.pageW, this.pageH, this.x, this.y, this.dw, this.dh);
}

/// Places a picture on a page. [margin] is in points.
Placement placeOnPage(int w, int h, String size, String orientation, double margin) {
  if (size == 'fit') {
    final pw = (w * 0.75).clamp(1.0, double.infinity);
    final ph = (h * 0.75).clamp(1.0, double.infinity);
    final m = [margin, pw / 4, ph / 4].reduce((a, b) => a < b ? a : b);
    return Placement(pw + m * 2, ph + m * 2, m, m, pw, ph);
  }
  var pw = kPageSizes[size]![0];
  var ph = kPageSizes[size]![1];
  final landscape = orientation == 'landscape' || (orientation == 'auto' && w > h);
  if (landscape) {
    final t = pw;
    pw = ph;
    ph = t;
  }
  final aw = pw - margin * 2, ah = ph - margin * 2;
  final s = (aw / w) < (ah / h) ? aw / w : ah / h;
  final dw = w * s, dh = h * s;
  return Placement(pw, ph, (pw - dw) / 2, (ph - dh) / 2, dw, dh);
}
