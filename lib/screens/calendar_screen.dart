import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/dose_status.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../ui/dose_widgets.dart';
import '../ui/format.dart';

/// Weekly medication calendar built from saved schedules (including schedule
/// revisions). Follow-up reminders are not doses and never appear here.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.medicines,
    required this.onTake,
    this.isBusy,
    this.clock,
  });

  /// Reads the latest saved medicines (they change after marking doses).
  final List<Medicine> Function() medicines;
  final Future<void> Function(Medicine medicine, DateTime dose, bool taken)
      onTake;
  final bool Function()? isBusy;
  final DateTime Function()? clock;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];

  late DateTime _selected = _day(_now());
  bool _working = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Sunday of the selected week (calendar arithmetic; DST-safe).
  DateTime get _weekStart => DateTime(
      _selected.year, _selected.month, _selected.day - (_selected.weekday % 7));

  void _moveWeek(int weeks) => setState(() => _selected =
      DateTime(_selected.year, _selected.month, _selected.day + 7 * weeks));

  Future<void> _take(Medicine m, DateTime dose, bool value) async {
    if (_working || (widget.isBusy?.call() ?? false)) return;
    setState(() => _working = true);
    try {
      await widget.onTake(m, dose, value);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = _now();
    final today = _day(now);
    final medicines = widget.medicines();
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i)
    ];
    final doses = DoseTracking.dosesOn(medicines, _selected);
    final counts = DoseTracking.countDay(medicines, _selected, now);
    final isFuture = _selected.isAfter(today);
    final dayLabel = _selected == today ? 'today' : 'on ${Fmt.date(_selected)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Medication Calendar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            IconButton(
                tooltip: 'Previous week',
                onPressed: () => _moveWeek(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Semantics(
                header: true,
                child: Text('${_months[_selected.month - 1]} ${_selected.year}',
                    textAlign: TextAlign.center, style: textTheme.titleLarge),
              ),
            ),
            IconButton(
                tooltip: 'Next week',
                onPressed: () => _moveWeek(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          if (_selected != today)
            Center(
              child: TextButton(
                  onPressed: () => setState(() => _selected = today),
                  child: const Text('Go to Today')),
            ),
          const SizedBox(height: 4),
          Row(children: [
            for (final day in days)
              Expanded(
                child: _DayCell(
                  day: day,
                  label: _weekdays[day.weekday % 7],
                  selected: day == _selected,
                  isToday: day == today,
                  hasDoses: DoseTracking.dosesOn(medicines, day).isNotEmpty,
                  onTap: () => setState(() => _selected = day),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          SectionHeader(Fmt.longDate(_selected),
              icon: Icons.event_note_outlined,
              subtitle: doses.isEmpty
                  ? null
                  : '${doses.length} scheduled '
                      '${doses.length == 1 ? "dose" : "doses"}'),
          if (doses.isEmpty)
            const EmptyState(
              title: 'No doses scheduled',
              message: 'There are no scheduled medication doses on this day. '
                  'As-needed (PRN) medicines are not shown on the calendar.',
              leading: Icon(Icons.event_available_outlined,
                  size: 56, color: AppColors.primary),
            )
          else ...[
            if (!isFuture) DayProgressCard(counts: counts, dayLabel: dayLabel),
            for (final (m, dose) in doses)
              DoseCard(
                medicine: m,
                dose: dose,
                now: now,
                busy: _working || (widget.isBusy?.call() ?? false),
                allowTaking: !isFuture,
                onChanged: (value) => _take(m, dose, value),
              ),
          ],
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.selected,
    required this.isToday,
    required this.hasDoses,
    required this.onTap,
  });
  final DateTime day;
  final String label;
  final bool selected;
  final bool isToday;
  final bool hasDoses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '${Fmt.longDate(day)}${isToday ? ", today" : ""}'
          '${hasDoses ? ", has scheduled doses" : ""}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isToday ? AppColors.primary : AppColors.divider,
                width: isToday && !selected ? 2 : 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          selected ? Colors.white : AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text('${day.day}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: foreground)),
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasDoses
                      ? (selected ? AppColors.mint : AppColors.primary)
                      : Colors.transparent,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
