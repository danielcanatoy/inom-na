import 'package:http/http.dart' as http;

/// Thrown when the user cancelled a scan. Late results are discarded.
class ScanCancelled implements Exception {
  const ScanCancelled();
}

/// Cancellation and progress for one scan. Network requests made through
/// [client] are aborted on cancel. Native OCR cannot be interrupted, so its
/// result is simply ignored once cancelled.
class ScanControl {
  ScanControl({this.onStage});
  final void Function(String stage)? onStage;
  final _clients = <http.Client>[];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final client in _clients) {
      client.close(); // Aborts in-flight Ollama requests.
    }
  }

  /// Throws [ScanCancelled] if the user cancelled.
  void check() {
    if (_cancelled) throw const ScanCancelled();
  }

  void stage(String text) {
    if (!_cancelled) onStage?.call(text);
  }

  http.Client client() {
    final client = http.Client();
    _clients.add(client);
    if (_cancelled) client.close();
    return client;
  }
}

/// Non-sensitive facts about a scan (counts only, never prescription text).
class ScanDiagnostics {
  const ScanDiagnostics({
    required this.textLength,
    required this.ocrFailed,
    required this.found,
    required this.usedLaptop,
  });
  final int textLength;
  final bool ocrFailed;
  final int found;
  final bool usedLaptop;

  String get summary => [
        ocrFailed
            ? 'Text recognition failed on this phone'
            : 'Text recognized on this phone: $textLength characters',
        'Medicines found: $found',
      ].join(' · ');
}
