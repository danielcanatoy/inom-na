/// Flags strengths that deserve a second look against the original
/// prescription. It NEVER changes or substitutes a strength; the user must
/// compare and confirm, and ask a pharmacist when unsure.
class StrengthCheck {
  static final _amount = RegExp(
    r'(\d+(?:\.\d+)?|\.\d+)\s*(mcg|µg|ug|mg|g)\b',
    caseSensitive: false,
  );

  /// Above these single-strength amounts (in mg) a value is unusual for a
  /// tablet/capsule and is often a misread (e.g. an extra zero).
  static const _genericMaxMg = {'mg': 1000.0, 'g': 1000.0, 'mcg': 1.0};

  /// Highest commonly available single-unit oral strength (mg) for a few
  /// medicines in the app's list. Used only to prompt a double-check.
  static const _usualMaxMg = {
    'levothyroxine': 0.3, // 300 mcg
    'digoxin': 0.25, // 250 mcg
    'amlodipine': 10.0,
    'losartan': 100.0,
    'atorvastatin': 80.0,
    'rosuvastatin': 40.0,
    'simvastatin': 80.0,
    'warfarin': 10.0,
    'amoxicillin': 1000.0,
    'metformin': 1000.0,
  };

  /// Converts the first strength in [text] to mg, or null if none.
  static ({double mg, String shown})? strengthOf(String text) {
    final match = _amount.firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match[1]!);
    if (value == null) return null;
    final unit = match[2]!.toLowerCase();
    final mg = switch (unit) {
      'g' => value * 1000,
      'mg' => value,
      _ => value / 1000, // mcg / µg / ug
    };
    return (mg: mg, shown: match[0]!.trim());
  }

  static String _unitKey(String shown) {
    final unit = _amount.firstMatch(shown)![2]!.toLowerCase();
    return unit == 'g' || unit == 'mg' ? unit : 'mcg';
  }

  static String _fmt(double mg) => mg < 1
      ? '${(mg * 1000).round()} mcg'
      : '${mg == mg.roundToDouble() ? mg.toInt() : mg} mg';

  /// Reasons to double-check [dose] for medicine [name]. [sourceText] is the
  /// original prescription text, if available.
  static List<String> concerns(String name, String dose, {String? sourceText}) {
    final strength = strengthOf(dose);
    if (strength == null) return const [];
    final result = <String>[];
    final key = name.trim().toLowerCase();
    final usual = _usualMaxMg.entries
        .where((e) => key.startsWith(e.key))
        .map((e) => e.value)
        .firstOrNull;
    if (usual != null && strength.mg > usual + 1e-9) {
      result.add('${strength.shown} is higher than the usual single-tablet '
          'strengths of ${name.trim()} (up to ${_fmt(usual)}).');
    } else if (usual == null &&
        strength.mg > _genericMaxMg[_unitKey(strength.shown)]!) {
      result.add('${strength.shown} is an unusually large strength for one '
          'tablet or capsule.');
    }
    final written =
        sourceText == null ? null : _writtenStrength(name, sourceText);
    if (written != null && (written.mg - strength.mg).abs() > 1e-9) {
      result.add('The prescription text shows ${written.shown}, but the '
          'strength here is ${strength.shown}.');
    }
    return result;
  }

  /// The strength written right after [name] in the original text, if any.
  static ({double mg, String shown})? _writtenStrength(
      String name, String text) {
    final word = name.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (word.length < 4) return null;
    for (final line in text.split('\n')) {
      final lower = line.toLowerCase();
      final at = lower.indexOf(word);
      if (at < 0) continue;
      return strengthOf(line.substring(at + word.length));
    }
    return null;
  }
}
