import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/medicine.dart';

/// Medicine records are stored on the phone; extraction may use the LAN laptop.
class Store {
  static late SharedPreferences _p;
  static Future<void> _writes = Future<void>.value();
  static String? loadError;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    loadError = null;
    _writes = Future<void>.value();
  }

  static List<Medicine> meds() {
    final raw = _p.getString('meds');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      final medicines = decoded
          .map((e) => Medicine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (medicines.map((m) => m.id).toSet().length != medicines.length) {
        throw const FormatException();
      }
      loadError = null;
      return medicines;
    } catch (_) {
      loadError = 'Hindi mabasa ang naka-save na gamot. Napanatili ang orihinal na data; '
          'hindi muna ito papalitan.';
      return [];
    }
  }

  static Future<void> saveMeds(List<Medicine> meds) {
    // Capture a snapshot before awaiting: later UI mutations cannot change it.
    final encoded = jsonEncode(meds.map((m) => m.toJson()).toList());
    final duplicateIds = meds.map((m) => m.id).toSet().length != meds.length;
    final operation = _writes.then((_) async {
      if (loadError != null || duplicateIds) {
        throw StateError('Hindi ligtas palitan ang naka-save na gamot.');
      }
      final previous = _p.getString('meds');
      // Also protect callers that did not load records before their first write.
      if (previous != null) {
        meds();
        if (loadError != null) {
          throw StateError('Hindi ligtas palitan ang naka-save na gamot.');
        }
      }
      if (previous != null && !_p.containsKey('meds_phase1_backup')) {
        if (!await _p.setString('meds_phase1_backup', previous)) {
          throw StateError('Hindi nagawa ang backup ng mga gamot.');
        }
      }
      if (!await _p.setString('meds', encoded)) {
        throw StateError('Hindi na-save ang mga gamot.');
      }
    });
    _writes = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  // Ollama sa laptop (pareho dapat ang WiFi/hotspot ng phone at laptop)
  static String get ollamaUrl => _p.getString('ollamaUrl') ?? 'http://192.168.1.81:11434';
  static String get ollamaModel => _p.getString('ollamaModel') ?? 'qwen2.5:3b';
  static String get visionModel => _p.getString('visionModel') ?? 'qwen2.5vl:3b';

  /// Accept only local IP endpoints. Public hosts, credentials, and URL queries
  /// are rejected before any prescription is transmitted.
  static Uri localOllamaUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !isLocalHost(uri.host)) {
      throw const FormatException('Gumamit ng lokal na IP ng laptop at port ng Ollama.');
    }
    return uri.replace(path: '');
  }

  static bool isLocalHost(String host) {
    final normalized = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (normalized == 'localhost' || normalized == '::1') return true;
    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    return (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  static Future<void> setOllama(String url, String model, String vision) async {
    final endpoint = localOllamaUri(url);
    if (model.trim().isEmpty ||
        [model, vision].any((m) => RegExp(r'(^|[:/\-])cloud($|[:/\-])',
            caseSensitive: false).hasMatch(m.trim()))) {
      throw const FormatException('Pumili ng lokal na text/vision model.');
    }
    if (!await _p.setString('ollamaUrl', endpoint.toString()) ||
        !await _p.setString('ollamaModel', model.trim()) ||
        !await _p.setString('visionModel', vision.trim())) {
      throw StateError('Hindi na-save ang Local AI settings.');
    }
  }
}
