import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/medicine.dart';
import '../services/ocr.dart';
import '../services/rx_parser.dart';
import '../services/scheduler.dart';
import '../services/store.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../ui/brand.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import 'confirm_screen.dart';
import '../services/dose_status.dart';
import '../ui/dose_widgets.dart';
import '../ui/routine_suggestion.dart';
import 'calendar_screen.dart';
import 'edit_schedule_screen.dart';
import 'medication_details_screen.dart';
import 'routine_screen.dart';
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
        : result.message ?? 'Reminders are not ready.');
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
          : 'Your medications were saved. '
              '${result.message ?? "The reminder could not be set."}';
      if (mounted) setState(() => _notice = notice);
      return SchedulerResult(
          success: result.success, message: notice, exact: result.exact);
    } catch (_) {
      final message = stored
          ? 'Your medications were saved, but reminders could not be fully updated.'
          : 'The change could not be saved. Your previous medications were kept.';
      if (mounted) setState(() => _notice = message);
      return SchedulerResult(success: false, message: message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<T> _withLoading<T>(
      String title, String message, Future<T> Function() action) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessingDialog(title: title, message: message),
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
        'Reading your prescription…',
        'Text is recognized on this phone. If your laptop AI (Ollama) is '
            'connected, it interprets the prescription. This can take 1–2 minutes.',
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
      _snack(
          'The prescription could not be read. Try again or type it instead.',
          retry: () => unawaited(_scan(source)));
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
          title: const Text(AppStrings.typePrescription),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Type or paste the prescription exactly as written. '
                  'IMedsU reads it the same way as a scan, and you will '
                  'review every detail before saving.'),
              const SizedBox(height: 12),
              TextField(
                  controller: ctrl,
                  maxLines: 6,
                  minLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Prescription text',
                      alignLabelWithHint: true,
                      hintText: 'Amoxicillin 500mg\n1 cap TID x 7 days #21')),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text(AppStrings.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(c, ctrl.text),
                child: const Text('Read Prescription')),
          ],
        ),
      );
      if (text == null || text.trim().isEmpty || !mounted) return;
      final result = await _withLoading(
          'Reading the prescription text…',
          'Using the laptop AI if it is connected, otherwise the offline '
              'reader on this phone.',
          () => RxParser.parse(text));
      if (mounted) await _openConfirm(result, text);
    } catch (_) {
      _snack('Reading did not finish. Please try again.',
          retry: () => unawaited(_typeRx()));
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
                ? 'Saved. As-needed (PRN) medications have no scheduled reminders.'
                : 'Saved. Reminders are set for ${saved.length} '
                    '${saved.length == 1 ? "medication" : "medications"}.')
        : outcome.message ?? 'The reminder could not be set.');
  }

  Future<void> _take(Medicine medicine, DateTime dose, bool value) async {
    if (_saving) return;
    final candidate = _snapshot();
    final target = candidate.firstWhere((m) => m.id == medicine.id);
    // Records the actual confirmation time; the scheduled time is unchanged.
    if (!target.markTaken(dose, value: value, at: DateTime.now())) return;
    final result = await _commit(candidate,
        takenMedicine: value ? target : null, takenDose: value ? dose : null);
    if (result != null && !result.success) {
      _snack(result.message ?? 'The change could not be completed.');
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
          ? result.message ??
              'Test reminder set. It should appear in about 1 minute.'
          : result.message ?? 'The test reminder could not be set.');
      if (mounted) setState(() => _notice = result.message);
    } catch (_) {
      _snack('The test reminder could not be set. Check Android settings.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves confirmed schedule edits through the normal serialized save and
  /// reminder reconciliation. Taken records are merged, never dropped.
  Future<void> _applyRevised(List<Medicine> revised, String success) async {
    if (revised.isEmpty) return;
    final byId = {for (final m in revised) m.id: m};
    final candidate = [
      for (final m in _snapshot())
        if (byId[m.id] case final updated?)
          (updated
            ..taken = {...updated.taken, ...m.taken}.toList()
            ..takenAt = {...m.takenAt, ...updated.takenAt})
        else
          m,
    ];
    final result = await _commit(candidate);
    if (result == null) return;
    _snack(result.success
        ? result.message ?? success
        : result.message ?? 'The change could not be completed.');
  }

  Future<void> _openRoutine() async {
    if (_saving) return;
    final result = await Navigator.push<RoutineResult>(
        context,
        MaterialPageRoute(
            builder: (_) => RoutineScreen(medicines: _snapshot())));
    if (!mounted || result == null) return;
    setState(() {}); // Refresh routine-dependent prompts.
    if (result.updated.isEmpty) {
      _snack('Your daily routine was saved.');
      return;
    }
    await _applyRevised(
        result.updated,
        'Your daily routine was saved. Reminder times were updated for '
        '${result.updated.length} '
        '${result.updated.length == 1 ? "medication" : "medications"}.');
  }

  Future<void> _editSchedule(Medicine m) async {
    if (_saving) return;
    final revised = await Navigator.push<Medicine>(
        context,
        MaterialPageRoute(
            builder: (_) => EditScheduleScreen(medicine: m.copy())));
    if (!mounted || revised == null) return;
    await _applyRevised([revised], 'Schedule updated. Reminders were reset.');
  }

  Future<void> _openDetails(Medicine m) async {
    if (_saving) return;
    final revised = await Navigator.push<Medicine>(
        context,
        MaterialPageRoute(
            builder: (_) => MedicationDetailsScreen(medicine: m.copy())));
    if (!mounted || revised == null) return;
    await _applyRevised([revised], 'Schedule updated. Reminders were reset.');
  }

  Future<void> _openCalendar() async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => CalendarScreen(
                  medicines: () => _meds,
                  isBusy: () => _saving,
                  onTake: _take,
                )));
    if (mounted) setState(() {});
  }

  void _pickSource() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _ScanSourceSheet(onSelected: (option) {
              Navigator.pop(c);
              switch (option) {
                case _ScanOption.camera:
                  unawaited(_scan(ImageSource.camera));
                case _ScanOption.gallery:
                  unawaited(_scan(ImageSource.gallery));
                case _ScanOption.type:
                  unawaited(_typeRx());
              }
            }));
  }

  void _snack(String msg, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      action: retry == null
          ? null
          : SnackBarAction(label: 'Try Again', onPressed: retry),
    ));
  }

  bool get _canScan => !_saving && !_processing && Store.loadError == null;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDoses = DoseTracking.dosesOn(_meds, now);
    final lowStock = _meds.where(
        (m) => m.needsRefill && !m.isFinished && (m.daysLeft ?? 99) <= 3);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        // Scales down on narrow phones so the action icons always fit.
        title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: IMedsULogo(fontSize: 26)),
        actions: [
          IconButton(
              tooltip: 'My Daily Routine',
              icon: const Icon(Icons.wb_twilight),
              onPressed: _saving ? null : _openRoutine),
          IconButton(
              tooltip: 'Send a test reminder in 1 minute',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: _saving ? null : _testReminder),
          IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          const SizedBox(width: 4),
        ],
      ),
      // A fixed bar (not a floating button) so it never covers a card or
      // its Mark as Taken / Undo actions.
      bottomNavigationBar: _meds.isEmpty
          ? null
          : Material(
              color: AppColors.surface,
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: _canScan ? _pickSource : null,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text(AppStrings.scanPrescription)),
                  ),
                ),
              ),
            ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(Fmt.longDate(now),
                style: textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary)),
            if (_saving) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_notice != null)
              InfoBanner(
                tone: Store.loadError != null ? Tone.error : Tone.warning,
                message: _notice,
                action: Store.loadError != null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                            onPressed: _saving
                                ? null
                                : () async {
                                    await Scheduler.requestPermissions();
                                    await _refreshReminders();
                                  },
                            child: const Text('Check Reminders Again')),
                      ),
              ),
            if (Store.routine == null && Store.loadError == null)
              InfoBanner(
                tone: Tone.info,
                title: 'My Daily Routine',
                message: 'Set your usual wake-up, meal and bed times to get '
                    'reminder suggestions that fit your day.',
                action: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: _saving ? null : _openRoutine,
                      icon: const Icon(Icons.wb_twilight),
                      label: const Text('Set Up My Daily Routine')),
                ),
              ),
            if (_meds.isEmpty)
              EmptyState(
                leading: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                      color: AppColors.primaryLight, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const CapsuleMark(size: 56),
                ),
                title: 'Welcome to IMedsU',
                message: '${AppStrings.tagline}\n\n'
                    'Scan a prescription or pharmacy label. You will review '
                    'every detail before any reminder is set.',
                action: FilledButton.icon(
                    onPressed: _canScan ? _pickSource : null,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text(AppStrings.scanPrescription)),
              ),
            for (final m in lowStock)
              InfoBanner(
                tone: Tone.warning,
                title: 'Running low: ${m.name}',
                message:
                    'About ${m.daysLeft!.clamp(0, 99).floor()} days left based '
                    'on your stock. Please arrange a refill.',
              ),
            if (_meds.isNotEmpty) ...[
              const SectionHeader("Today's Medication Schedule",
                  icon: Icons.today_outlined),
              DayProgressCard(
                  counts: DoseTracking.countDay(_meds, now, now),
                  dayLabel: 'today'),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                    onPressed: _saving ? null : _openCalendar,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Medication Calendar')),
              ),
              const SizedBox(height: 4),
              _NextDose(meds: _meds, now: now),
              if (todayDoses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No doses are scheduled for today.'),
                ),
              for (final (m, d) in todayDoses)
                DoseCard(
                  medicine: m,
                  dose: d,
                  now: now,
                  busy: _saving,
                  onChanged: (value) => unawaited(_take(m, d, value)),
                ),
              const SectionHeader('My Medications',
                  icon: Icons.medication_outlined),
              for (final m in _meds) _medCard(m, now),
            ],
          ]),
    );
  }

  Widget _medCard(Medicine m, DateTime now) {
    final due = DoseTracking.countDue(m, now);
    final total = m.totalDoses;
    final textTheme = Theme.of(context).textTheme;
    final lines = [
      m.frequencyLabel,
      if (m.times.isNotEmpty && m.scheduleKind != ScheduleKind.interval)
        'Times: ${m.times.map(Fmt.clock).join(', ')}',
      if (due.total > 0)
        'Taken: ${due.taken}/${due.total} doses due so far'
            '${due.missed > 0 ? ' · Missed: ${due.missed}' : ''}',
      if (total != null)
        'Marked taken: ${m.taken.toSet().length} of $total planned doses',
      if (m.allTaken) 'All scheduled doses are marked taken.',
      if (m.isFinished)
        'Schedule finished (this does not confirm every dose was taken).',
      if (m.legacy)
        'Saved by an earlier version: the original schedule was kept. '
            'Compare it with your prescription.',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _saving ? null : () => _openDetails(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.name} ${m.dose}'.trim(),
                        style: textTheme.titleMedium),
                    const SizedBox(height: 4),
                    ScheduleBasisBadge(m),
                    if (m.instructions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(m.instructions, style: textTheme.bodySmall),
                      ),
                    const SizedBox(height: 6),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(line, style: textTheme.bodyMedium),
                      ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: _saving ? null : () => _editSchedule(m),
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: const Text('Edit Schedule')),
                      TextButton(
                          onPressed: _saving ? null : () => _openDetails(m),
                          child: const Text('Details')),
                    ]),
                  ]),
            ),
            IconButton(
                tooltip: 'Delete ${m.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                                    title: Text('Delete ${m.name}?'),
                                    content: const Text(
                                        'Its reminders will be cancelled and its '
                                        'dose history removed. This cannot be undone.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text(AppStrings.cancel)),
                                      FilledButton(
                                          style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.error),
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text(AppStrings.delete)),
                                    ]));
                        if (ok == true && mounted && !_saving) {
                          final candidate = _snapshot()
                            ..removeWhere((item) => item.id == m.id);
                          final result = await _commit(candidate);
                          if (result != null && !result.success) {
                            _snack(result.message ??
                                'The change could not be completed.');
                          }
                        }
                      }),
          ]),
        ),
      ),
    );
  }
}

/// The next scheduled dose that has not been marked taken.
class _NextDose extends StatelessWidget {
  const _NextDose({required this.meds, required this.now});
  final List<Medicine> meds;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    (Medicine, DateTime)? next;
    final horizon = now.add(const Duration(days: 2));
    for (final m in meds) {
      for (final d in m.allDoses(horizon: horizon, from: now)) {
        if (!d.isAfter(now) || m.isTaken(d)) continue;
        if (next == null || d.isBefore(next.$2)) next = (m, d);
        break;
      }
    }
    if (next == null) return const SizedBox.shrink();
    final (m, d) = next;
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final when = day == today
        ? 'Today'
        : day == today.add(const Duration(days: 1))
            ? 'Tomorrow'
            : Fmt.date(d);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.alarm, color: AppColors.primary, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Next dose', style: textTheme.bodySmall),
              Text('$when · ${Fmt.time(d)}', style: textTheme.titleMedium),
              Text('${m.qtyLabel} × ${m.name} ${m.dose}'.trim(),
                  style: textTheme.bodyMedium),
            ]),
          ),
        ]),
      ),
    );
  }
}

enum _ScanOption { camera, gallery, type }

class _ScanSourceSheet extends StatelessWidget {
  const _ScanSourceSheet({required this.onSelected});
  final ValueChanged<_ScanOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget option(
            _ScanOption value, IconData icon, String title, String subtitle) =>
        Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.primaryDark,
                child: Icon(icon)),
            title: Text(title, style: textTheme.titleMedium),
            subtitle: Text(subtitle),
            onTap: () => onSelected(value),
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add a Prescription', style: textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Choose how to add your prescription.',
                  style: textTheme.bodyMedium),
              const SizedBox(height: 12),
              option(
                  _ScanOption.camera,
                  Icons.photo_camera_outlined,
                  AppStrings.takePhoto,
                  'Place the prescription flat in good light and fill the '
                  'frame. Printed text works best.'),
              option(
                  _ScanOption.gallery,
                  Icons.photo_library_outlined,
                  AppStrings.chooseFromGallery,
                  'Use a clear photo you already took.'),
              option(
                  _ScanOption.type,
                  Icons.keyboard_outlined,
                  AppStrings.typePrescription,
                  'Type or paste the prescription text instead of a photo.'),
              const SizedBox(height: 8),
              Text(
                  'How it works: text is recognized on this phone. If your '
                  'laptop AI (Ollama) is connected on the same Wi-Fi or '
                  'hotspot, the photo and text are sent to it for '
                  'interpretation. Otherwise, the offline reader on this '
                  'phone is used. You will review everything before saving.',
                  style: textTheme.bodySmall),
            ]),
      ),
    );
  }
}
