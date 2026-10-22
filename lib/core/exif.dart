// Minimal EXIF reader for JPEG files (port of lib/exif.ts). Nothing leaves the phone.
import 'dart:typed_data';

class Exif {
  String? make, model, software, taken, lens;
  double? lat, lon;
  bool get any => [make, model, software, taken, lens, lat].any((e) => e != null);
}

const _typeSize = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8};

class _En {
  final int type, count, at;
  _En(this.type, this.count, this.at);
}

Exif? parseExif(Uint8List buf) {
  try {
    final v = ByteData.view(buf.buffer, buf.offsetInBytes, buf.lengthInBytes);
    if (v.lengthInBytes < 12 || v.getUint16(0) != 0xffd8) return null;
    var p = 2;
    while (p + 4 <= v.lengthInBytes) {
      if (v.getUint8(p) != 0xff) break;
      final marker = v.getUint8(p + 1);
      if (marker == 0xda || marker == 0xd9) break;
      final len = v.getUint16(p + 2);
      if (marker == 0xe1 && p + 10 <= v.lengthInBytes && v.getUint32(p + 4) == 0x45786966 && v.getUint16(p + 8) == 0) {
        return _readTiff(v, p + 10);
      }
      p += 2 + len;
    }
  } catch (_) {}
  return null;
}

Exif? _readTiff(ByteData v, int t) {
  final little = v.getUint16(t) == 0x4949;
  final endian = little ? Endian.little : Endian.big;
  int u16(int o) => v.getUint16(o, endian);
  int u32(int o) => v.getUint32(o, endian);

  Map<int, _En> ifd(int rel) {
    final m = <int, _En>{};
    final o = t + rel;
    if (o + 2 > v.lengthInBytes) return m;
    final n = u16(o);
    for (var i = 0; i < n; i++) {
      final e = o + 2 + i * 12;
      if (e + 12 > v.lengthInBytes) break;
      m[u16(e)] = _En(u16(e + 2), u32(e + 4), e + 8);
    }
    return m;
  }

  int dataAt(_En en) {
    final size = (_typeSize[en.type] ?? 1) * en.count;
    return size <= 4 ? en.at : t + u32(en.at);
  }

  String? str(_En? en) {
    if (en == null) return null;
    final o = dataAt(en);
    if (en.count > 512 || o + en.count > v.lengthInBytes) return null;
    final sb = StringBuffer();
    for (var i = 0; i < en.count; i++) {
      final c = v.getUint8(o + i);
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    final s = sb.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<double> nums(_En? en) {
    if (en == null) return [];
    final o = dataAt(en);
    final cnt = en.count < 8 ? en.count : 8;
    final size = (_typeSize[en.type] ?? 1) * cnt;
    if (o + size > v.lengthInBytes) return [];
    final out = <double>[];
    for (var i = 0; i < cnt; i++) {
      switch (en.type) {
        case 1:
          out.add(v.getUint8(o + i).toDouble());
        case 3:
          out.add(u16(o + i * 2).toDouble());
        case 4:
          out.add(u32(o + i * 4).toDouble());
        case 9:
          out.add(v.getInt32(o + i * 4, endian).toDouble());
        case 5:
          final d = u32(o + i * 8 + 4);
          out.add(d != 0 ? u32(o + i * 8) / d : 0);
        case 10:
          final d = v.getInt32(o + i * 8 + 4, endian);
          out.add(d != 0 ? v.getInt32(o + i * 8, endian) / d : 0);
        default:
          return out;
      }
    }
    return out;
  }

  final i0 = ifd(u32(t + 4));
  final out = Exif()
    ..make = str(i0[0x010f])
    ..model = str(i0[0x0110])
    ..software = str(i0[0x0131]);
  final exifPtr = nums(i0[0x8769]).isNotEmpty ? nums(i0[0x8769])[0] : 0;
  if (exifPtr != 0) {
    final e = ifd(exifPtr.toInt());
    out.taken = str(e[0x9003]) ?? str(e[0x9004]);
    out.lens = str(e[0xa434]);
  }
  out.taken ??= str(i0[0x0132]);
  final gpsPtr = nums(i0[0x8825]).isNotEmpty ? nums(i0[0x8825])[0] : 0;
  if (gpsPtr != 0) {
    final g = ifd(gpsPtr.toInt());
    double? dms(List<double> a) => a.length >= 3 ? a[0] + a[1] / 60 + a[2] / 3600 : null;
    var lat = dms(nums(g[2]));
    var lon = dms(nums(g[4]));
    if (lat != null && lon != null && !(lat == 0 && lon == 0)) {
      if ((str(g[1]) ?? 'N').toUpperCase().startsWith('S')) lat = -lat;
      if ((str(g[3]) ?? 'E').toUpperCase().startsWith('W')) lon = -lon;
      out.lat = lat;
      out.lon = lon;
    }
  }
  return out.any ? out : null;
}

String? formatTaken(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2})').firstMatch(s);
  if (m == null) return s;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final mi = int.parse(m.group(2)!) - 1;
  if (mi < 0 || mi > 11) return s;
  return '${int.parse(m.group(3)!)} ${months[mi]} ${m.group(1)}, ${m.group(4)}:${m.group(5)}';
}

String formatCoords(double lat, double lon) =>
    '${lat.abs().toStringAsFixed(5)}° ${lat >= 0 ? 'N' : 'S'}, ${lon.abs().toStringAsFixed(5)}° ${lon >= 0 ? 'E' : 'W'}';
