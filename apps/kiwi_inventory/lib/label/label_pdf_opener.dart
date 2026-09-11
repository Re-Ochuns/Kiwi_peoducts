import 'dart:typed_data';

import 'label_pdf_opener_stub.dart'
    if (dart.library.html) 'label_pdf_opener_web.dart'
    as platform;

typedef LabelPdfOpener = Future<bool> Function(
  Uint8List bytes,
  String filename,
);

Future<bool> openLabelPdf(Uint8List bytes, String filename) =>
    platform.openLabelPdf(bytes, filename);
