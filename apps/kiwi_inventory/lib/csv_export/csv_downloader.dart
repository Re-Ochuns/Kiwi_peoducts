import 'dart:typed_data';

import 'csv_downloader_stub.dart'
    if (dart.library.html) 'csv_downloader_web.dart'
    as platform;

typedef CsvDownloader = Future<bool> Function(Uint8List bytes, String filename);

Future<bool> downloadCsv(Uint8List bytes, String filename) =>
    platform.downloadCsv(bytes, filename);
