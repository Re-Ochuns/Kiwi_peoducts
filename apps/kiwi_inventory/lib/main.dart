import 'package:flutter/material.dart';

void main() {
  runApp(const KiwiInventoryApp());
}

class KiwiInventoryApp extends StatelessWidget {
  const KiwiInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'キウイ在庫管理',
      home: Scaffold(body: Center(child: Text('キウイ在庫管理'))),
    );
  }
}
