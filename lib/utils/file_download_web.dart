import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Download [content] sebagai file [filename] lewat trik anchor
/// `<a download>` browser — standar untuk "Save As" tanpa dialog native
/// Flutter (tidak ada API file-system langsung di web).
bool downloadTextFile(String filename, String content) {
  final blob = web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: 'text/plain;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}
