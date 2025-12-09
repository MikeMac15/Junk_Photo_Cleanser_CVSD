import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cvsd/ui/desktop_scan_page.dart';
import 'package:cvsd/ui/android_scan_page.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screenshot Detector',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        // primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      // Automatically choose the page based on the platform
      home: Platform.isAndroid || Platform.isIOS 
          ? const AndroidScanPage() 
          : const DesktopScanPage(),
    );
  }
}