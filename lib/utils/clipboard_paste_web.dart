import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

StreamSubscription<web.ClipboardEvent>? _sub;

/// Dengarkan event paste (Ctrl+V) browser — kalau clipboard berisi gambar,
/// [onImage] dipanggil dengan nama file + bytes-nya. Aktif selama input bar
/// hidup (lihat initState/dispose di input_bar.dart) — tidak dibatasi cuma
/// saat TextField fokus, karena scoping presisi ke situ butuh akses ke
/// elemen DOM internal Flutter (rapuh/tidak stabil lintas versi Flutter).
void listenForImagePaste(void Function(String name, List<int> bytes) onImage) {
  _sub?.cancel();
  final body = web.document.body;
  if (body == null) return;
  _sub = body.onPaste.listen((event) async {
    final files = event.clipboardData?.files;
    if (files == null || files.length == 0) return;
    final file = files.item(0);
    if (file == null || !file.type.startsWith('image/')) return;
    final buffer = await file.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    final ext = file.type.contains('/') ? file.type.split('/').last : 'png';
    final name = file.name.isNotEmpty ? file.name : 'pasted_image.$ext';
    onImage(name, bytes);
  });
}

void stopListeningForImagePaste() {
  _sub?.cancel();
  _sub = null;
}
