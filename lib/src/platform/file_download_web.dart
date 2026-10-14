import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Saves [content] as a file through the browser download flow.
void downloadTextFile(String fileName, String content, String mimeType) {
  final blob = web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = fileName
        ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  unawaited(Future<void>.delayed(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url)));
}
