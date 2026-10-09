import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/medicine.dart';
import '../services/ocr.dart';
import '../services/rx_parser.dart';
import '../services/scheduler.dart';
import '../services/store.dart';
import 'confirm_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Medicine> _meds = [];

  @override
  void initState() {
    super.initState();
    _meds = Store.meds();
    Scheduler.requestPermissions();
  }

  Future<void> _save() async {
    await Store.saveMeds(_meds);
    await Scheduler.rescheduleAll(_meds);
    setState(() {});
  }

  // ---------- Pag-scan ----------
  Future<void> _scan(ImageSource source) async {
    // Max 1600px: sapat para sa OCR, at mas mabilis basahin ng vision model sa laptop
    final picked = await ImagePicker()
        .pickImage(source: source, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
    if (picked == null || !mounted) return;
    _showLoading('Binabasa ng Local AI ang reseta...\nPwedeng umabot ng 1–2 minuto.');
    try {
      final text = await Ocr.read(picked.path);
      // TEMP DEBUG: raw OCR text
      debugPrint('[RX] OCR TEXT (${text.length} chars):\n$text\n[RX] --- end OCR ---');
      final result = await RxParser.parseImage(picked.path, text);
      if (!mounted) return;
      Navigator.pop(context); // loading
      await _openConfirm(result, text);
    } catch (e) {
      debugPrint('[RX] SCAN ERROR: $e');
      if (!mounted) return;
      Navigator.pop(context);
      _snack('May error sa pagbasa: $e');
    }
  }

  Future<void> _typeRx() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('I-type ang reseta'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Amoxicillin 500mg\n1 cap TID x 7 days #21',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kanselahin')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Basahin')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    _showLoading('Iniintindi ang reseta...');
    final result = await RxParser.parse(text);
    if (!mounted) return;
    Navigator.pop(context);
    await _openConfirm(result, text);
  }

  Future<void> _openConfirm(ParseResult result, String rawText) async {
    final saved = await Navigator.push<List<Medicine>>(
      context,
      MaterialPageRoute(builder: (_) => ConfirmScreen(result: result, rawText: rawText)),
    );
    if (saved == null || saved.isEmpty) return;
    final now = DateTime.now();
    for (final m in saved) {
      m.start = now;
    }
    _meds.addAll(saved);
    await _save();
    _snack('Naka-set na ang ${saved.length} gamot. Magpapaalala kami. 💊');
  }

  void _pickSource() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Kunan ng picture'),
            onTap: () {
              Navigator.pop(c);
              _scan(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Pumili sa gallery'),
            onTap: () {
              Navigator.pop(c);
              _scan(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.keyboard),
            title: const Text('I-type na lang'),
            onTap: () {
              Navigator.pop(c);
              _typeRx();
            },
          ),
        ]),
      ),
    );
  }

  // ---------- Helpers ----------
  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(msg)),
        ]),
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final todayDoses = <(Medicine, DateTime)>[];
    for (final m in _meds) {
      for (final d in m.allDoses(horizon: tomorrow)) {
        if (!d.isBefore(today) && d.isBefore(tomorrow)) todayDoses.add((m, d));
      }
    }
    todayDoses.sort((a, b) => a.$2.compareTo(b.$2));

    final lowStock = _meds
        .where((m) => m.needsRefill && !m.isFinished && (m.daysLeft ?? 99) <= 3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inom Na! 💊'),
        actions: [
          IconButton(
            tooltip: 'Subukan ang paalala (1 minuto)',
            icon: const Icon(Icons.notifications_active),
            onPressed: () async {
              await Scheduler.testInOneMinute(_meds.isEmpty ? null : _meds.first);
              _snack('Tutunog ang paalala pagkalipas ng 1 minuto.');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickSource,
        icon: const Icon(Icons.document_scanner),
        label: const Text('I-scan ang reseta'),
      ),
      body: _meds.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final m in lowStock)
                  Card(
                    color: Colors.orange.shade100,
                    child: ListTile(
                      leading: const Icon(Icons.shopping_cart, color: Colors.deepOrange),
                      title: Text('Malapit nang maubos ang ${m.name}'),
                      subtitle: Text(
                          '${m.daysLeft!.clamp(0, 99).floor()} araw na lang. Bumili ka na.'),
                    ),
                  ),
                Text('Ngayong araw', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (todayDoses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Walang naka-schedule na gamot ngayon.'),
                  ),
                for (final (m, d) in todayDoses)
                  Card(
                    child: CheckboxListTile(
                      value: m.isTaken(d),
                      onChanged: (v) {
                        final k = Medicine.keyOf(d);
                        v == true ? m.taken.add(k) : m.taken.remove(k);
                        _save();
                      },
                      title: Text('${_fmt(d)} · ${m.name} ${m.dose}'),
                      subtitle: Text([
                        '${m.qtyLabel} piraso',
                        if (m.instructions.isNotEmpty) m.instructions,
                      ].join(' · ')),
                      secondary: Icon(
                        m.isTaken(d) ? Icons.check_circle : Icons.schedule,
                        color: m.isTaken(d)
                            ? Colors.green
                            : (d.isBefore(now) ? Colors.red : null),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Mga gamot ko', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final m in _meds) _medCard(m, now),
              ],
            ),
    );
  }

  Widget _medCard(Medicine m, DateTime now) {
    final due = m.allDoses(horizon: now).where((d) => !d.isAfter(now)).toList();
    final takenDue = due.where(m.isTaken).length;
    final total = m.totalDoses;
    return Card(
      child: ListTile(
        title: Text('${m.name} ${m.dose}'),
        subtitle: Text([
          m.frequencyLabel,
          if (m.times.isNotEmpty) 'Oras: ${m.times.join(', ')}',
          if (due.isNotEmpty) 'Nainom: $takenDue/${due.length} na dose',
          if (total != null) 'Kabuuan: ${m.taken.length}/$total',
          if (m.isFinished) '✅ Tapos na ang gamutan',
        ].join('\n')),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('Tanggalin ang ${m.name}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hindi')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oo')),
                ],
              ),
            );
            if (ok == true) {
              _meds.remove(m);
              await _save();
            }
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.medication_outlined, size: 72),
          SizedBox(height: 16),
          Text('Wala pang gamot', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            'Kunan ng picture ang reseta o label ng gamot.\nKami na ang magpapaalala, kahit walang internet.',
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
