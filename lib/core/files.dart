import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'codec.dart';

/// One picture the person chose: original bytes, a decoded copy and its file name.
class Pic {
  final String id;
  final String name;
  final Uint8List bytes;
  final ui.Image image;
  Pic(this.id, this.name, this.bytes, this.image);
  int get w => image.width;
  int get h => image.height;
}

int _counter = 0;

List<String> extsFromAccept(String accept) {
  final out = <String>{};
  for (final m in accept.split(',')) {
    switch (m.trim()) {
      case 'image/jpeg':
        out.addAll(['jpg', 'jpeg']);
      case 'image/png':
        out.add('png');
      case 'image/webp':
        out.add('webp');
      case 'image/gif':
        out.add('gif');
      case 'image/bmp':
        out.add('bmp');
      case 'image/avif':
        out.add('avif');
      case 'image/svg+xml':
        out.add('svg');
    }
  }
  return out.isEmpty ? ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'avif'] : out.toList();
}

/// Opens the system picker and decodes what was chosen. Throws a readable error for bad files.
Future<List<Pic>> pickPics({required String accept, bool multiple = true}) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extsFromAccept(accept), allowMultiple: multiple, withData: true);
  if (res == null) return [];
  final out = <Pic>[];
  String? firstError;
  for (final f in res.files) {
    try {
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      final img = await loadImage(bytes, f.name);
      out.add(Pic('p${_counter++}', f.name, bytes, img));
    } catch (_) {
      firstError ??= '${f.name} could not be opened. It may be damaged or an unsupported format.';
    }
  }
  if (out.isEmpty && firstError != null) throw Exception(firstError);
  return out;
}

String uniqueName(String name, Set<String> used) {
  var out = name;
  var n = 1;
  while (used.contains(out)) {
    out = name.replaceFirstMapped(RegExp(r'(\.[^.]+)$'), (m) => '-${n++}${m.group(1)}');
    if (!name.contains('.')) out = '$name-${n++}';
  }
  used.add(out);
  return out;
}

Uint8List zipFiles(List<MapEntry<String, Uint8List>> entries) {
  final arc = Archive();
  final used = <String>{};
  for (final e in entries) {
    arc.addFile(ArchiveFile(uniqueName(e.key, used), e.value.length, e.value));
  }
  final bytes = ZipEncoder().encode(arc, level: 0);
  return Uint8List.fromList(bytes!);
}

/// "Download": opens the system Save dialog. Returns true when a file was written.
Future<bool> saveToDevice(Uint8List bytes, String name) async {
  final path = await FilePicker.platform.saveFile(dialogTitle: 'Save $name', fileName: name, bytes: bytes);
  return path != null;
}

Future<void> saveToGallery(Uint8List bytes, String name) async {
  await Gal.putImageBytes(bytes, name: baseName2(name));
}

String baseName2(String n) => n.replaceFirst(RegExp(r'\.[^.]+$'), '');

Future<void> shareBytes(Uint8List bytes, String name, String mime) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(f.path, mimeType: mime)]);
}

Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));
