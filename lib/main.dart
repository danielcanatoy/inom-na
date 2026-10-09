import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/ocr_probe.dart';
import 'services/scheduler.dart';
import 'services/store.dart';
import 'ui/app_strings.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Scheduler.init();
  runApp(const InomNaApp());
  // Debug builds only: measures OCR on developer-placed synthetic images.
  unawaited(OcrProbe.runIfPresent());
}

class InomNaApp extends StatelessWidget {
  const InomNaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
