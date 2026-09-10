import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const goldenFontFamily = 'GoldenNotoSansJP';
const _fontRelativeToApp =
    '../../experiments/fnd-07/assets/NotoSansJP-VariableFont_wght.ttf';

Future<void> loadGoldenTestFont() async {
  final fontFile = File(_fontRelativeToApp);
  if (!fontFile.existsSync()) {
    throw StateError(
      'Golden font was not found. Run tests from apps/kiwi_inventory: '
      '${fontFile.absolute.path}',
    );
  }

  final bytes = await fontFile.readAsBytes();
  final loader = FontLoader(goldenFontFamily)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void configureGoldenView(WidgetTester tester, ui.Size logicalSize) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
