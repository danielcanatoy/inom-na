import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/med_names.dart';
import '../services/rx_parser.dart';

/// Every prescription field and the resulting schedule must be reviewed.
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({super.key, required this.result, required this.rawText});
  final ParseResult result;
  final String rawText;
  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late final List<Medicine> _meds =
      widget.result.meds.map((m) => Medicine.fromJson(m.toJson())).toList();
  final Set<String> _verified = {};
  final Set<String> _startReviewed = {};

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  List<String> _errors(Medicine m) => [
        ...m.validationErrors(),
        if (m.scheduleKind == ScheduleKind.interval &&
            !_startReviewed.contains(m.id))
          'Piliin ang petsa at oras ng unang dose para sa pagitan ng oras.',
        if (m.scheduleKind == ScheduleKind.interval &&
            m.intervalHours != null &&
            m.intervalHours! > 0 &&
            m.times.any((time) =>
                Medicine.validTime(time) &&
                (Medicine.atTime(m.start, time)
                            .difference(DateTime(m.start.year, m.start.month,
                                m.start.day, m.start.hour, m.start.minute))
                            .inMinutes %
                        (m.intervalHours! * 60) !=
                    0)))
          'Hindi tugma ang unang dose at pagitan sa nakasulat na oras. '
              'Itama ang oras gamit ang reseta bago kumpirmahin.',
      ];

  void _verify(Medicine m) {
    final errors = _errors(m);
    if (errors.isNotEmpty) {
      _message(errors.join('\n'));
      return;
    }
    setState(() => _verified.add(m.id));
  }

  void _save() {
    if (_meds.isEmpty) {
      _message('Magdagdag muna ng gamot.');
      return;
    }
    for (final m in _meds) {
      final errors = _errors(m);
      if (errors.isNotEmpty || !_verified.contains(m.id)) {
        _message(errors.isEmpty
            ? 'Suriin at kumpirmahin ang bawat gamot at iskedyul bago i-save.'
            : errors.join('\n'));
        return;
      }
    }
    Navigator.pop(context, _meds);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tama ba ang nabasa?')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Card(
                child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Binasa ng: ${widget.result.source}'),
                    if (widget.result.note != null) Text(widget.result.note!),
                    const SizedBox(height: 8),
                    const Text(
                        'Maaaring magkamali ang OCR at AI, kahit kilala ang pangalan. '
                        'Ikumpara ang bawat detalye at iskedyul sa reseta. '
                        'Kung malabo ang bilin o sulat-kamay, itanong sa doktor o pharmacist.',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                        'Maaaring ipadala ang larawan at OCR text sa Ollama laptop '
                        'sa lokal na network. Hindi encrypted ang HTTP connection. '
                        'Sa phone naka-save ang mga gamot at paalala.',
                        style: TextStyle(fontSize: 12)),
                  ]),
            )),
            ExpansionTile(
                title: const Text('Orihinal na text na nabasa'),
                children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                          widget.rawText.isEmpty ? '(wala)' : widget.rawText)),
                ]),
            for (final m in _meds)
              _MedEditor(
                key: ValueKey(m.id),
                med: m,
                warning: widget.result.warnings[m.id],
                verified: _verified.contains(m.id),
                startReviewed: _startReviewed.contains(m.id),
                onChanged: () => setState(() => _verified.remove(m.id)),
                onStartReviewed: () => setState(() {
                  _startReviewed.add(m.id);
                  _verified.remove(m.id);
                }),
                onVerify: () => _verify(m),
                onRemove: () => setState(() {
                  _meds.remove(m);
                  _verified.remove(m.id);
                  _startReviewed.remove(m.id);
                }),
              ),
            OutlinedButton.icon(
                onPressed: () => setState(
                    () => _meds.add(Medicine(id: Medicine.newId(), name: ''))),
                icon: const Icon(Icons.add),
                label: const Text('Magdagdag ng gamot')),
          ],
        ),
        bottomNavigationBar: SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.alarm_on),
              label: const Text('Tama na, i-set ang paalala')),
        )),
      );
}

enum _DurationChoice { unknown, days, end, maintenance }

class _MedEditor extends StatefulWidget {
  const _MedEditor({
    super.key,
    required this.med,
    required this.verified,
    required this.startReviewed,
    required this.onChanged,
    required this.onStartReviewed,
    required this.onVerify,
    required this.onRemove,
    this.warning,
  });
  final Medicine med;
  final bool verified;
  final bool startReviewed;
  final VoidCallback onChanged;
  final VoidCallback onStartReviewed;
  final VoidCallback onVerify;
  final VoidCallback onRemove;
  final String? warning;
  @override
  State<_MedEditor> createState() => _MedEditorState();
}

class _MedEditorState extends State<_MedEditor> {
  Medicine get m => widget.med;
  late _DurationChoice _duration = !m.durationConfirmed
      ? _DurationChoice.unknown
      : m.days != null
          ? _DurationChoice.days
          : m.end != null
              ? _DurationChoice.end
              : _DurationChoice.maintenance;

  void _change(VoidCallback edit) {
    setState(edit);
    widget.onChanged();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final day = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(initial.year < 2000 ? initial.year : 2000),
        lastDate: DateTime(initial.year > 2100 ? initial.year : 2100, 12, 31));
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(m.start);
    if (picked == null || !mounted) return;
    _change(() => m.start = picked);
    widget.onStartReviewed();
  }

  Future<void> _pickEnd() async {
    final picked =
        await _pickDateTime(m.end ?? m.start.add(const Duration(days: 7)));
    if (picked == null || !mounted) return;
    _change(() {
      m.end = picked;
      m.days = null;
      m.durationConfirmed = true;
    });
  }

  Future<void> _editTime(int? index) async {
    final base = index == null ? '08:00' : m.times[index];
    final initial = Medicine.validTime(base)
        ? TimeOfDay(
            hour: int.parse(base.substring(0, 2)),
            minute: int.parse(base.substring(3)))
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    if (m.times
        .asMap()
        .entries
        .any((entry) => entry.key != index && entry.value == value)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nakalagay na ang oras na ito.')));
      return;
    }
    _change(() {
      if (index == null) {
        m.times.add(value);
      } else {
        m.times[index] = value;
      }
      m.times.sort();
    });
  }

  InputDecoration _dec(String label, [String? hint]) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final nameWarning = MedNames.check(m.name).warning;
    final errors = m.validationErrors();
    final preview = errors.isEmpty
        ? m.allDoses(
            from: m.start, horizon: m.start.add(const Duration(days: 2)))
        : <DateTime>[];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.warning != null)
            Text('Babala mula sa unang pagbasa:\n${widget.warning!}'),
          if (nameWarning != null) Text(nameWarning),
          for (final note in m.reviewNotes) Text('Suriin: $note'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextFormField(
                    initialValue: m.name,
                    decoration: _dec('Gamot', 'hal. Amoxicillin'),
                    onChanged: (v) => _change(() => m.name = v.trim()))),
            IconButton(
                onPressed: widget.onRemove, icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextFormField(
                    initialValue: m.dose,
                    decoration: _dec('Dose / strength', 'hal. 500 mg'),
                    onChanged: (v) => _change(() => m.dose = v.trim()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextFormField(
                    initialValue: m.qtyPerIntake > 0 ? m.qtyLabel : '',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('Dami kada inom', 'hal. 1 tablet o 5 mL'),
                    onChanged: (v) => _change(
                        () => m.qtyPerIntake = double.tryParse(v) ?? 0))),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<ScheduleKind>(
            value: m.scheduleKind,
            // Fit the card width and wrap long values instead of overflowing.
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            decoration: _dec('Uri ng iskedyul ayon sa reseta'),
            items: const [
              DropdownMenuItem(
                  value: ScheduleKind.unknown, child: Text('Hindi pa malinaw')),
              DropdownMenuItem(
                  value: ScheduleKind.daily,
                  child: Text('Bilang kada araw (OD/BID/TID/QID)')),
              DropdownMenuItem(
                  value: ScheduleKind.interval,
                  child: Text('Eksaktong pagitan (q6h/q8h)')),
              DropdownMenuItem(
                  value: ScheduleKind.explicit,
                  child: Text('Nakasulat na oras')),
              DropdownMenuItem(
                  value: ScheduleKind.prn,
                  child: Text('Kapag kailangan (PRN, walang paalala)')),
            ],
            onChanged: (kind) {
              if (kind != null) _change(() => m.scheduleKind = kind);
            },
          ),
          const SizedBox(height: 10),
          if (m.scheduleKind == ScheduleKind.daily)
            TextFormField(
                key: const ValueKey('daily-frequency'),
                initialValue: m.frequencyPerDay?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _dec('Bilang kada araw'),
                onChanged: (v) =>
                    _change(() => m.frequencyPerDay = int.tryParse(v))),
          if (m.scheduleKind == ScheduleKind.interval) ...[
            TextFormField(
                key: const ValueKey('interval-hours'),
                initialValue: m.intervalHours?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _dec('Pagitan sa oras', 'hal. 8 para sa q8h'),
                onChanged: (v) =>
                    _change(() => m.intervalHours = int.tryParse(v))),
            if (m.times.isNotEmpty)
              Text('Nabasa sa reseta: ${m.times.join(', ')}. '
                  'Gamitin sa pagpili ng unang dose; hindi ito kapalit ng pagitan.'),
            if (!widget.startReviewed)
              const Text('Kailangang piliin ang unang dose sa ibaba.'),
          ],
          if (m.scheduleKind == ScheduleKind.daily ||
              m.scheduleKind == ScheduleKind.explicit ||
              m.scheduleKind == ScheduleKind.interval) ...[
            Text(m.scheduleKind == ScheduleKind.daily
                ? 'Mungkahing oras para sa dalas kada araw. Ayusin ayon sa reseta bago kumpirmahin.'
                : m.scheduleKind == ScheduleKind.interval
                    ? 'Mga nakasulat na oras para sa interval. Itama kung mali ang basa; '
                        'dapat tumugma ang unang dose at pagitan sa mga ito.'
                    : 'Nabasa o inilagay na oras. Ikumpara sa reseta bago kumpirmahin.'),
            Wrap(spacing: 6, children: [
              for (var i = 0; i < m.times.length; i++)
                InputChip(
                    label: Text(m.times[i]),
                    onPressed: () => _editTime(i),
                    onDeleted: () => _change(() => m.times.removeAt(i))),
              ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Oras'),
                  onPressed: () => _editTime(null)),
            ]),
          ],
          TextButton(
              onPressed: _pickStart,
              child: Text('Simula / unang dose: ${Medicine.keyOf(m.start)}')),
          const SizedBox(height: 10),
          DropdownButtonFormField<_DurationChoice>(
            value: _duration,
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            decoration: _dec('Tagal ayon sa reseta'),
            items: const [
              DropdownMenuItem(
                  value: _DurationChoice.unknown,
                  child: Text('Hindi pa malinaw')),
              DropdownMenuItem(
                  value: _DurationChoice.days, child: Text('Bilang ng araw')),
              DropdownMenuItem(
                  value: _DurationChoice.end,
                  child: Text('Petsa at oras ng pagtatapos')),
              DropdownMenuItem(
                  value: _DurationChoice.maintenance,
                  child: Text('Maintenance (kumpirmadong tuloy-tuloy)')),
            ],
            onChanged: (choice) {
              if (choice == null) return;
              _change(() {
                _duration = choice;
                if (choice != _DurationChoice.days) m.days = null;
                if (choice != _DurationChoice.end) m.end = null;
                m.durationConfirmed = choice == _DurationChoice.maintenance ||
                    (choice == _DurationChoice.days &&
                        m.days != null &&
                        m.days! > 0) ||
                    (choice == _DurationChoice.end && m.end != null);
              });
            },
          ),
          if (_duration == _DurationChoice.days)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextFormField(
                    key: const ValueKey('duration-days'),
                    initialValue: m.days?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: _dec('Ilang araw'),
                    onChanged: (v) => _change(() {
                          m.days = int.tryParse(v);
                          m.end = null;
                          m.durationConfirmed = m.days != null && m.days! > 0;
                        }))),
          if (_duration == _DurationChoice.end)
            TextButton(
                onPressed: _pickEnd,
                child: Text(m.end == null
                    ? 'Piliin ang pagtatapos'
                    : 'Wala nang dose mula: ${Medicine.keyOf(m.end!)}')),
          const SizedBox(height: 10),
          TextFormField(
              initialValue: m.stock?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: _dec('Stock / dami na nabili', 'optional'),
              onChanged: (v) => _change(() => m.stock = int.tryParse(v))),
          const SizedBox(height: 10),
          TextFormField(
              initialValue: m.instructions,
              maxLines: null,
              decoration: _dec('Bilin (panatilihin at linawin ang malabo)'),
              onChanged: (v) => _change(() => m.instructions = v.trim())),
          const SizedBox(height: 10),
          if (errors.isNotEmpty)
            Text(errors.join('\n'),
                style: TextStyle(color: Colors.red.shade800)),
          if (preview.isNotEmpty) ...[
            const Text('Unang mga nakatakdang dose:'),
            Text(preview.take(8).map(Medicine.keyOf).join('\n')),
          ],
          if (m.scheduleEnd != null)
            Text('Wala nang dose mula: ${Medicine.keyOf(m.scheduleEnd!)}'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.verified,
              title: const Text('Nasuri ko na ang pangalan, dose, dami, '
                  'bilin, tagal at iskedyul sa reseta.'),
              onChanged: (checked) {
                if (checked == true) {
                  widget.onVerify();
                } else {
                  widget.onChanged();
                }
              }),
        ]),
      ),
    );
  }
}
