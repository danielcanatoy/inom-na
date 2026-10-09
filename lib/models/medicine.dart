/// Isang gamot sa reseta at ang schedule nito.
class Medicine {
  Medicine({
    required this.id,
    required this.name,
    this.dose = '',
    this.qtyPerIntake = 1,
    List<String>? times,
    this.days,
    this.instructions = '',
    this.stock,
    DateTime? start,
    List<String>? taken,
  })  : times = times ?? [],
        start = start ?? DateTime.now(),
        taken = taken ?? [];

  String id;
  String name;
  String dose; // hal. "500mg"
  double qtyPerIntake; // ilang tableta kada inom
  List<String> times; // "HH:mm"; walang laman = PRN (kapag kailangan)
  int? days; // null = maintenance / tuloy-tuloy
  String instructions; // hal. "pagkatapos kumain"
  int? stock; // ilang piraso ang nabili
  DateTime start;
  List<String> taken; // mga dose key na nainom na

  int get timesPerDay => times.length;
  bool get isMaintenance => days == null;
  bool get isPrn => times.isEmpty;
  int? get totalDoses => days == null ? null : days! * timesPerDay;

  String get qtyLabel => qtyPerIntake == qtyPerIntake.roundToDouble()
      ? qtyPerIntake.toInt().toString()
      : qtyPerIntake.toString();

  String get frequencyLabel {
    if (isPrn) return 'Kapag kailangan (PRN)';
    final f = '${timesPerDay}x kada araw';
    return days == null ? '$f · maintenance' : '$f · $days araw';
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  static DateTime atTime(DateTime day, String hhmm) {
    final p = hhmm.split(':');
    return DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
  }

  static String keyOf(DateTime dt) =>
      '${dt.year}-${_2(dt.month)}-${_2(dt.day)} ${_2(dt.hour)}:${_2(dt.minute)}';
  static String _2(int n) => n.toString().padLeft(2, '0');

  /// Karaniwang oras base sa dami ng inom kada araw (pwedeng i-edit ng user).
  static List<String> defaultTimes(int perDay, {bool bedtime = false}) {
    if (perDay <= 0) return [];
    if (bedtime && perDay == 1) return ['21:00'];
    switch (perDay) {
      case 1:
        return ['08:00'];
      case 2:
        return ['08:00', '20:00'];
      case 3:
        return ['08:00', '14:00', '20:00'];
      case 4:
        return ['06:00', '12:00', '18:00', '22:00'];
      default:
        final step = 24 ~/ perDay;
        return List.generate(perDay, (i) => '${_2((6 + i * step) % 24)}:00');
    }
  }

  /// Lahat ng dose. Ang gamutan ay nagsisimula sa unang oras na kasunod ng [start]
  /// at tatapusin ang buong bilang (days x timesPerDay), para kumpleto ang antibiotic.
  /// Para sa maintenance, hanggang [horizon] lang.
  List<DateTime> allDoses({required DateTime horizon}) {
    if (times.isEmpty) return [];
    final sorted = [...times]..sort();
    final total = totalDoses;
    final from = start.subtract(const Duration(minutes: 30));
    final out = <DateTime>[];
    var day = DateTime(start.year, start.month, start.day);
    while (true) {
      for (final t in sorted) {
        final dt = atTime(day, t);
        if (dt.isBefore(from)) continue;
        if (total != null && out.length >= total) return out;
        if (total == null && dt.isAfter(horizon)) return out;
        out.add(dt);
      }
      day = DateTime(day.year, day.month, day.day + 1);
      if (total == null && day.isAfter(horizon)) return out;
    }
  }

  bool isTaken(DateTime dose) => taken.contains(keyOf(dose));

  bool get isFinished {
    final total = totalDoses;
    if (total == null) return false;
    final doses = allDoses(horizon: DateTime.now());
    return doses.isNotEmpty && DateTime.now().isAfter(doses.last.add(const Duration(hours: 6)));
  }

  /// Ilang araw pa bago maubos ang stock (null kung hindi alam ang stock).
  double? get daysLeft {
    if (stock == null || isPrn) return null;
    final remaining = stock! - taken.length * qtyPerIntake;
    return remaining / (timesPerDay * qtyPerIntake);
  }

  /// Kailangan bang bumili pa? (kulang ang nabili para sa buong gamutan o maintenance)
  bool get needsRefill {
    if (stock == null || isPrn) return false;
    final total = totalDoses;
    if (total != null && stock! >= total * qtyPerIntake) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'qtyPerIntake': qtyPerIntake,
        'times': times,
        'days': days,
        'instructions': instructions,
        'stock': stock,
        'start': start.toIso8601String(),
        'taken': taken,
      };

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'] as String,
        name: j['name'] as String,
        dose: (j['dose'] ?? '') as String,
        qtyPerIntake: (j['qtyPerIntake'] as num?)?.toDouble() ?? 1,
        times: (j['times'] as List?)?.cast<String>(),
        days: j['days'] as int?,
        instructions: (j['instructions'] ?? '') as String,
        stock: j['stock'] as int?,
        start: DateTime.tryParse(j['start'] as String? ?? ''),
        taken: (j['taken'] as List?)?.cast<String>(),
      );
}
