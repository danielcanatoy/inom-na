import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/medicine.dart';

/// Lahat ng data ay nasa phone lang (walang cloud).
class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static List<Medicine> meds() {
    final raw = _p.getString('meds');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveMeds(List<Medicine> meds) =>
      _p.setString('meds', jsonEncode(meds.map((m) => m.toJson()).toList()));

  // Ollama sa laptop (pareho dapat ang WiFi/hotspot ng phone at laptop)
  static String get ollamaUrl => _p.getString('ollamaUrl') ?? 'http://192.168.1.81:11434';
  static String get ollamaModel => _p.getString('ollamaModel') ?? 'qwen2.5:3b';
  static String get visionModel => _p.getString('visionModel') ?? 'qwen2.5vl:3b';

  static Future<void> setOllama(String url, String model, String vision) async {
    await _p.setString('ollamaUrl', url.trim().replaceAll(RegExp(r'/+$'), ''));
    await _p.setString('ollamaModel', model.trim());
    await _p.setString('visionModel', vision.trim());
  }
}
