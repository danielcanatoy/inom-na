import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/scheduler.dart';
import 'services/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Scheduler.init();
  runApp(const InomNaApp());
}

class InomNaApp extends StatelessWidget {
  const InomNaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inom Na!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1B7F5A),
      ),
      home: const HomeScreen(),
    );
  }
}
