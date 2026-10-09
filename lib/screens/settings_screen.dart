import 'package:flutter/material.dart';

import '../services/rx_parser.dart';
import '../services/store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController(text: Store.ollamaUrl);
  final _model = TextEditingController(text: Store.ollamaModel);
  final _vision = TextEditingController(text: Store.visionModel);
  String? _status;
  bool _busy = false;

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await Store.setOllama(_url.text, _model.text, _vision.text);
      final s = await RxParser.ping();
      if (mounted) setState(() => _status = s);
    } on FormatException catch (e) {
      if (mounted) setState(() => _status = e.message.toString());
    } catch (_) {
      if (mounted)
        setState(
            () => _status = 'Hindi na-save o nasubukan ang Local AI settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _vision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local AI (Ollama)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'Ang Ollama ay tumatakbo sa laptop. Ikonekta ang phone sa parehong WiFi o hotspot. '
          'Walang internet na kailangan.\n\n'
          'Sa laptop:  OLLAMA_HOST=0.0.0.0 ollama serve\n'
          'Hanapin ang IP ng laptop (ipconfig / ifconfig).\n'
          'Sa lokal na IP ng laptop ipinapadala ang larawan at buong OCR text. '
          'Gumamit ng lokal na models at pinagkakatiwalaang WiFi. '
          'Ang http connection ay hindi encrypted.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'Ollama URL',
            hintText: 'http://192.168.1.10:11434',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          decoration: const InputDecoration(
            labelText: 'Text model',
            hintText: 'qwen2.5:3b',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _vision,
          decoration: const InputDecoration(
            labelText: 'Vision model (para sa sulat-kamay)',
            hintText: 'qwen2.5vl:3b  (blangko = huwag gamitin)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _test,
          child: Text(_busy ? 'Sinusubukan...' : 'I-save at subukan'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          Text(_status!),
        ],
        const SizedBox(height: 24),
        const Text(
          'Kapag hindi maabot ang Ollama, gagana pa rin ang app gamit ang offline parser sa phone.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }
}
