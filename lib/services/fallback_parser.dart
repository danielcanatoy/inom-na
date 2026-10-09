import '../models/medicine.dart';

/// Rule-based na parser na tumatakbo sa phone mismo.
/// Backup ito kapag walang Ollama, at para sa karaniwang format lang.
class FallbackParser {
  static final _medLine = RegExp(
    r'([A-Za-z][A-Za-z\-\+ ]{2,40}?)\s*(\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu)(?:\s*/\s*\d+(?:\.\d+)?\s*(?:mg|ml))?)',
    caseSensitive: false,
  );
  static final _qHours = RegExp(r'\bq\s*(\d{1,2})\s*h', caseSensitive: false);
  static final _f4 = RegExp(r'\b(qid|4x|4\s*times)\b', caseSensitive: false);
  static final _f3 = RegExp(r'\b(tid|3x|thrice|3\s*times)\b', caseSensitive: false);
  static final _f2 = RegExp(r'\b(bid|2x|twice|2\s*times)\b', caseSensitive: false);
  static final _f1 = RegExp(r'\b(od|qd|once|1x|once\s*a\s*day|daily|isang\s*beses)\b', caseSensitive: false);
  static final _bed = RegExp(r'\b(hs|bedtime|at\s*night|bago\s*matulog)\b', caseSensitive: false);
  static final _prn = RegExp(r'\b(prn|as\s*needed|kung\s*kailangan|kapag\s*kailangan)\b', caseSensitive: false);
  static final _days = RegExp(
      r'(?:x|for|sa\s*loob\s*ng)?\s*(\d{1,3})\s*(days?|araw|weeks?|wks?|linggo)\b',
      caseSensitive: false);
  static final _maint = RegExp(r'\b(maintenance|continue|tuloy)\b', caseSensitive: false);
  static final _stock = RegExp(r'(?:#|qty\.?:?|no\.)\s*(\d{1,4})\b', caseSensitive: false);
  static final _qty = RegExp(r'(\d+(?:\.\d+)?|1/2|½)\s*(tabs?|tablets?|caps?|capsules?|tsp)\b',
      caseSensitive: false);
  static final _ac = RegExp(r'\b(ac|before\s*meals?|bago\s*kumain)\b', caseSensitive: false);
  static final _pc = RegExp(r'\b(pc|after\s*meals?|pagkatapos\s*kumain|with\s*food)\b',
      caseSensitive: false);
  static final _notName = RegExp(r'^(sig|take|inumin|rx|qty|no)\b', caseSensitive: false);

  static List<Medicine> parse(String text) {
    final drafts = <_Draft>[];
    _Draft? cur;

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final m = _medLine.firstMatch(line);
      if (m != null) {
        final name = _cleanName(m.group(1)!);
        if (name.length >= 3 && !_notName.hasMatch(name)) {
          cur = _Draft(name, m.group(2)!.replaceAll(' ', ''));
          drafts.add(cur);
        }
      }
      if (cur != null) _apply(cur, line);
    }

    return [
      for (var i = 0; i < drafts.length; i++)
        Medicine(
          id: '${Medicine.newId()}$i',
          name: drafts[i].name,
          dose: drafts[i].dose,
          qtyPerIntake: drafts[i].qty ?? 1,
          times: drafts[i].prn
              ? []
              : Medicine.defaultTimes(drafts[i].perDay ?? 1, bedtime: drafts[i].bedtime),
          days: drafts[i].maintenance ? null : drafts[i].days,
          instructions: drafts[i].instructions ?? '',
          stock: drafts[i].stock,
        ),
    ];
  }

  static void _apply(_Draft d, String line) {
    final q = _qHours.firstMatch(line);
    if (q != null) {
      final h = int.parse(q.group(1)!);
      if (h > 0 && h <= 24) d.perDay ??= 24 ~/ h;
    }
    if (_f4.hasMatch(line)) d.perDay ??= 4;
    if (_f3.hasMatch(line)) d.perDay ??= 3;
    if (_f2.hasMatch(line)) d.perDay ??= 2;
    if (_bed.hasMatch(line)) {
      d.bedtime = true;
      d.perDay ??= 1;
    }
    if (_f1.hasMatch(line)) d.perDay ??= 1;
    if (_prn.hasMatch(line)) d.prn = true;
    if (_maint.hasMatch(line)) d.maintenance = true;

    final dm = _days.firstMatch(line);
    if (dm != null && d.days == null) {
      final n = int.parse(dm.group(1)!);
      final unit = dm.group(2)!.toLowerCase();
      d.days = (unit.startsWith('w') || unit == 'linggo') ? n * 7 : n;
    }
    final sm = _stock.firstMatch(line);
    if (sm != null) d.stock ??= int.parse(sm.group(1)!);

    final qm = _qty.firstMatch(line);
    if (qm != null && d.qty == null) {
      final v = qm.group(1)!;
      d.qty = (v == '1/2' || v == '½') ? 0.5 : double.tryParse(v);
    }
    if (_ac.hasMatch(line)) d.instructions ??= 'bago kumain';
    if (_pc.hasMatch(line)) d.instructions ??= 'pagkatapos kumain';
  }

  static String _cleanName(String s) => s
      .replaceAll(RegExp(r'^\s*(\d+[\.\)]|rx:?|r/)\s*', caseSensitive: false), '')
      .trim();
}

class _Draft {
  _Draft(this.name, this.dose);
  final String name;
  final String dose;
  int? perDay;
  int? days;
  int? stock;
  double? qty;
  String? instructions;
  bool bedtime = false;
  bool prn = false;
  bool maintenance = false;
}
