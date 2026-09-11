import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> openLabelPdf(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final opened = web.window.open(url, filename);
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
  return opened != null;
}
