import 'dart:async';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Medicine> _meds = [];
  bool _saving = false;
  bool _processing = false;
  bool _checkingReminders = false;
  String? _notice;
  Timer? _clockRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _meds = Store.meds();
    _notice = Store.loadError;
    unawaited(_refreshReminders());
    _clockRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {});
      unawaited(_refreshReminders());
    }
  }

  Future<void> _refreshReminders() async {
    if (_saving || _checkingReminders || Store.loadError != null) return;
    _checkingReminders = true;
    final result = await Scheduler.rescheduleAll(_snapshot());
    _checkingReminders = false;
    if (!mounted || _saving) return;
    setState(() => _notice = result.success
        ? result.message
        : result.message ?? 'Hindi handa ang mga paalala.');
  }

  List<Medicine> _snapshot() =>
      _meds.map((m) => Medicine.fromJson(m.toJson())).toList();

  /// UI actions use immutable snapshots and cannot overlap persistence.
  Future<SchedulerResult?> _commit(List<Medicine> candidate,
      {Medicine? takenMedicine, DateTime? takenDose}) async {
    if (_saving || Store.loadError != null) return null;
    setState(() => _saving = true);
    var stored = false;
    try {
      await Store.saveMeds(candidate);
      stored = true;
      if (mounted) setState(() => _meds = candidate);
      final result = takenMedicine != null && takenDose != null
          ? await Scheduler.cancelDose(takenMedicine, takenDose)
          : await Scheduler.rescheduleAll(candidate);
      final notice = result.success
          ? result.message
          : 'Naka-save ang mga gamot, ngunit ${result.message ?? "hindi nairehistro ang paalala."}';
      if (mounted) setState(() => _notice = notice);
      return SchedulerResult(
          success: result.success, message: notice, exact: result.exact);
    } catch (_) {
      final message = stored
          ? 'Naka-save ang mga gamot, ngunit hindi nakumpleto ang mga paalala.'
          : 'Hindi na-save ang pagbabago. Napanatili ang dating mga gamot.';
      if (mounted) setState(() => _notice = message);
      return SchedulerResult(success: false, message: message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<T> _withLoading<T>(String message, Future<T> Function() action) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ]),
          )),
    );
    unawaited(navigator.push<void>(route));
    try {
      return await action();
    } finally {
      if (route.isActive) navigator.removeRoute(route);
    }
  }

  Future<void> _scan(ImageSource source) async {
    if (_processing || _saving || Store.loadError != null) return;
    setState(() => _processing = true);
    try {
      final picked = await ImagePicker().pickImage(
          source: source, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
      if (picked == null || !mounted) return;
      var text = '';
      final result = await _withLoading(
        'Binabasa ng Local AI ang reseta...\nPwedeng umabot ng 1–2 minuto.',
        () async {
          try {
            text = await Ocr.read(picked.path);
          } catch (_) {
            // Vision extraction can still work; no prescription/error logging.
          }
          return RxParser.parseImage(picked.path, text);
        },
      );
      if (mounted) await _openConfirm(result, text);
    } catch (_) {
      _snack('Hindi mabasa ang reseta. Subukan muli o i-type ang nakasulat.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _typeRx() async {
    if (_processing || _saving || Store.loadError != null) return;
    setState(() => _processing = true);
    final ctrl = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('I-type ang reseta'),
          content: TextField(
              controller: ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                  hintText: 'Amoxicillin 500mg\n1 cap TID x 7 days #21',
                  border: OutlineInputBorder())),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Kanselahin')),
            FilledButton(
                onPressed: () => Navigator.pop(c, ctrl.text),
                child: const Text('Basahin')),
          ],
        ),
      );
      if (text == null || text.trim().isEmpty || !mounted) return;
      final result = await _withLoading(
          'Iniintindi ang reseta...', () => RxParser.parse(text));
      if (mounted) await _openConfirm(result, text);
    } catch (_) {
      _snack('Hindi nakumpleto ang pagbasa. Subukan muli.');
    } finally {
      ctrl.dispose();
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openConfirm(ParseResult result, String rawText) async {
    final saved = await Navigator.push<List<Medicine>>(
        context,
        MaterialPageRoute(
            builder: (_) => ConfirmScreen(result: result, rawText: rawText)));
    if (!mounted || saved == null || saved.isEmpty) return;
    // Preserve the reviewed start, end and interval anchor.
    await Scheduler.requestPermissions();
    if (!mounted) return;
    final outcome = await _commit([..._snapshot(), ...saved]);
    if (outcome == null) return;
    _snack(outcome.success
        ? outcome.message ??
            (saved.every((m) => m.isPrn)
                ? 'Naka-save ang PRN na gamot. Walang naka-schedule na paalala para rito.'
                : 'Naka-save at nairehistro ang paalala para sa ${saved.length} gamot.')
        : outcome.message ?? 'Hindi nairehistro ang paalala.');
  }

  Future<void> _take(Medicine medicine, DateTime dose, bool value) async {
    if (_saving) return;
    final candidate = _snapshot();
    final target = candidate.firstWhere((m) => m.id == medicine.id);
    if (!target.markTaken(dose, value: value)) return;
    final result = await _commit(candidate,
        takenMedicine: value ? target : null, takenDose: value ? dose : null);
    if (result != null && !result.success) {
      _snack(result.message ?? 'Hindi nakumpleto ang pagbabago.');
    }
  }

  Future<void> _testReminder() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Scheduler.requestPermissions();
      final result =
          await Scheduler.testInOneMinute(_meds.isEmpty ? null : _meds.first);
      _snack(result.success
          ? result.message ?? 'Nairehistro ang test reminder para sa 1 minuto.'
          : result.message ?? 'Hindi nairehistro ang test reminder.');
      if (mounted) setState(() => _notice = result.message);
    } catch (_) {
      _snack(
          'Hindi nairehistro ang test reminder. Suriin ang Android settings.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                      unawaited(_scan(ImageSource.camera));
                    }),
                ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('Pumili sa gallery'),
                    onTap: () {
                      Navigator.pop(c);
                      unawaited(_scan(ImageSource.gallery));
                    }),
                ListTile(
                    leading: const Icon(Icons.keyboard),
                    title: const Text('I-type na lang'),
                    onTap: () {
                      Navigator.pop(c);
                      unawaited(_typeRx());
                    }),
              ]),
            ));
  }

  void _snack(String msg) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? "AM" : "PM"}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final todayDoses = <(Medicine, DateTime)>[];
    for (final m in _meds) {
      for (final d in m.allDoses(horizon: tomorrow, from: today)) {
        if (d.isBefore(tomorrow)) todayDoses.add((m, d));
      }
    }
    todayDoses.sort((a, b) => a.$2.compareTo(b.$2));
    final lowStock = _meds.where(
        (m) => m.needsRefill && !m.isFinished && (m.daysLeft ?? 99) <= 3);

    return Scaffold(
      appBar: AppBar(title: const Text('Inom Na! 💊'), actions: [
        IconButton(
            tooltip: 'Subukan ang paalala (1 minuto)',
            icon: const Icon(Icons.notifications_active),
            onPressed: _saving ? null : _testReminder),
        IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving || _processing || Store.loadError != null
              ? null
              : _pickSource,
          icon: const Icon(Icons.document_scanner),
          label: const Text('I-scan ang reseta')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (_notice != null)
              Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_notice!),
                          if (Store.loadError == null)
                            TextButton(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        await Scheduler.requestPermissions();
                                        await _refreshReminders();
                                      },
                                child: const Text(
                                    'Suriin / subukan muli ang paalala')),
                        ]),
                  )),
            if (_saving) const LinearProgressIndicator(),
            if (_meds.isEmpty) const _Empty(),
            for (final m in lowStock)
              Card(
                  color: Colors.orange.shade100,
                  child: ListTile(
                      leading: const Icon(Icons.shopping_cart,
                          color: Colors.deepOrange),
                      title: Text('Malapit nang maubos ang ${m.name}'),
                      subtitle: Text(
                          '${m.daysLeft!.clamp(0, 99).floor()} araw na lang.'))),
            if (_meds.isNotEmpty) ...[
              Text('Ngayong araw',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (todayDoses.isEmpty)
                const Text('Walang naka-schedule na gamot ngayon.'),
              for (final (m, d) in todayDoses)
                Card(
                    child: CheckboxListTile(
                        value: m.isTaken(d),
                        onChanged: _saving
                            ? null
                            : (v) => unawaited(_take(m, d, v == true)),
                        title: Text('${_fmt(d)} · ${m.name} ${m.dose}'),
                        subtitle: Text([
                          'Dami: ${m.qtyLabel}',
                          if (m.instructions.isNotEmpty) m.instructions,
                        ].join(' · ')),
                        secondary: Icon(
                            m.isTaken(d) ? Icons.check_circle : Icons.schedule,
                            color: m.isTaken(d)
                                ? Colors.green
                                : (d.isBefore(now) ? Colors.red : null)))),
              const SizedBox(height: 16),
              Text('Mga gamot ko',
                  style: Theme.of(context).textTheme.titleLarge),
              for (final m in _meds) _medCard(m, now),
            ],
          ]),
    );
  }

  Widget _medCard(Medicine m, DateTime now) {
    final due = m.allDoses(horizon: now);
    final takenDue = due.where(m.isTaken).length;
    final total = m.totalDoses;
    return Card(
        child: ListTile(
      title: Text('${m.name} ${m.dose}'),
      subtitle: Text([
        m.frequencyLabel,
        if (m.legacy)
          'Dating record: napanatili ang orihinal na iskedyul. '
              'Hindi nito pinatutunayang tama ang dating pagbasa; ikumpara sa reseta.',
        if (m.times.isNotEmpty && m.scheduleKind != ScheduleKind.interval)
          'Oras: ${m.times.join(', ')}',
        if (due.isNotEmpty) 'Nainom: $takenDue/${due.length} na dose',
        if (total != null)
          'Nakatalang nainom: ${m.taken.toSet().length}/$total',
        if (m.allTaken) 'Nainom lahat ng nakatakdang dose',
        if (m.isFinished)
          'Natapos ang iskedyul; hindi ito patunay na nainom lahat.',
      ].join('\n')),
      trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: _saving
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                              title: Text('Tanggalin ang ${m.name}?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Hindi')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Oo')),
                              ]));
                  if (ok == true && mounted && !_saving) {
                    final candidate = _snapshot()
                      ..removeWhere((item) => item.id == m.id);
                    final result = await _commit(candidate);
                    if (result != null && !result.success) {
                      _snack(
                          result.message ?? 'Hindi nakumpleto ang pagbabago.');
                    }
                  }
                }),
    ));
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.medication_outlined, size: 72),
          SizedBox(height: 16),
          Text('Wala pang gamot',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
              'Kunan ng picture ang reseta o label ng gamot. '
              'Suriin muna ang detalye bago mag-set ng offline na paalala.',
              textAlign: TextAlign.center),
        ]),
      );
}
