enum NameStatus { known, corrected, uncertain, unknown }

class NameCheck {
  NameCheck(this.name, this.status, this.warning);
  final String name; // Name to use (original if uncertain)
  final NameStatus status;
  final String? warning; // null = nothing to review
}

/// Common medications in the Philippines + correction of small misreadings
/// (e.g. "Amoxicilin" -> "Amoxicillin"). Runs offline on the phone.
/// The user still confirms every detail on the ConfirmScreen.
class MedNames {
  static const common = [
    // Antibiotics
    'Amoxicillin', 'Co-Amoxiclav', 'Cefalexin', 'Cefuroxime', 'Cefixime',
    'Azithromycin', 'Clarithromycin', 'Ciprofloxacin', 'Levofloxacin',
    'Doxycycline', 'Clindamycin', 'Metronidazole', 'Cotrimoxazole',
    'Nitrofurantoin', 'Cloxacillin',
    // Pain / fever
    'Paracetamol', 'Ibuprofen', 'Mefenamic Acid', 'Naproxen', 'Celecoxib',
    'Tramadol', 'Aspirin',
    // Heart / blood pressure
    'Losartan', 'Amlodipine', 'Metoprolol', 'Atenolol', 'Carvedilol',
    'Bisoprolol', 'Captopril', 'Enalapril', 'Lisinopril', 'Telmisartan',
    'Valsartan', 'Hydrochlorothiazide', 'Furosemide', 'Spironolactone',
    'Felodipine', 'Nifedipine', 'Clopidogrel', 'Isosorbide Mononitrate',
    'Trimetazidine', 'Digoxin', 'Warfarin',
    // Diabetes / cholesterol
    'Metformin', 'Gliclazide', 'Glimepiride', 'Sitagliptin',
    'Atorvastatin', 'Rosuvastatin', 'Simvastatin',
    // Stomach
    'Omeprazole', 'Pantoprazole', 'Esomeprazole', 'Famotidine',
    'Domperidone', 'Metoclopramide', 'Loperamide', 'Hyoscine',
    // Allergy / cough / asthma
    'Cetirizine', 'Loratadine', 'Diphenhydramine', 'Chlorphenamine',
    'Salbutamol', 'Montelukast', 'Ambroxol', 'Carbocisteine',
    'Guaifenesin', 'Lagundi', 'Sambong',
    // Others
    'Prednisone', 'Prednisolone', 'Dexamethasone', 'Methylprednisolone',
    'Allopurinol',
    'Colchicine', 'Levothyroxine', 'Ferrous Sulfate', 'Folic Acid',
    'Ascorbic Acid', 'Calcium Carbonate', 'Betahistine', 'Cinnarizine',
    'Mebendazole', 'Albendazole', 'Isoniazid', 'Rifampicin', 'Ethambutol',
    'Pyrazinamide', 'Oseltamivir', 'Acyclovir', 'Fluconazole', 'Tamsulosin',
    'Gabapentin', 'Pregabalin', 'Sertraline', 'Fluoxetine',
  ];

  /// Checks a name that was read. SAFETY: only small typos are corrected
  /// (max 1 letter for 5–9 letters, max 2 for 10+; none below 5 letters).
  /// Ambiguous, distant or look-alike names are left unchanged with a warning.
  static NameCheck check(String name) {
    final input = name.trim();
    final lower = input.toLowerCase();
    if (input.isEmpty) return NameCheck(input, NameStatus.unknown, null);

    final ranked = [
      for (final c in common) (distance(lower, c.toLowerCase()), c)
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final (bestD, best) = ranked[0];
    final secondD = ranked[1].$1;
    if (bestD == 0) return NameCheck(best, NameStatus.known, null);

    final maxD = lower.length < 5 ? 0 : (lower.length <= 9 ? 1 : 2);
    final clearWinner =
        secondD > bestD + 1; // no other medication is nearly as close
    final sameStart = lower[0] == best[0].toLowerCase();
    if (bestD <= maxD && clearWinner && sameStart) {
      return NameCheck(best, NameStatus.corrected,
          "Read as '$input' → corrected to '$best'. Please check.");
    }

    final near = [
      for (final r in ranked)
        if (r.$1 <= maxD + 1) r.$2
    ].take(2).toList();
    if (near.isNotEmpty) {
      return NameCheck(
          input,
          NameStatus.uncertain,
          "Read as '$input'. Not sure: could it be ${near.map((n) => "'$n'").join(' or ')}? "
          'Please check your prescription.');
    }
    return NameCheck(input, NameStatus.unknown,
        "'$input' is not in the app's medication list. Please check the spelling on your prescription.");
  }

  /// Conservative suggestions for a name read by OCR/AI: only close matches
  /// from this app's short list (not a complete drug database). Empty when
  /// the name is listed, unknown, or too uncertain. Never applied
  /// automatically; the user must pick one or type the name.
  static List<String> suggestions(String name) {
    final c = check(name);
    switch (c.status) {
      case NameStatus.corrected:
        return [c.name];
      case NameStatus.uncertain:
        final lower = name.trim().toLowerCase();
        final maxD = lower.length < 5 ? 0 : (lower.length <= 9 ? 1 : 2);
        return [
          for (final known in common)
            if (distance(lower, known.toLowerCase()) <= maxD + 1) known
        ].take(2).toList();
      case NameStatus.known:
      case NameStatus.unknown:
        return const [];
    }
  }

  /// Review note for a name, phrased as a question (nothing is changed).
  static String? reviewNote(String name) {
    final c = check(name);
    final input = name.trim();
    final options = suggestions(name);
    return switch (c.status) {
      NameStatus.known => null,
      NameStatus.corrected || NameStatus.uncertain => "Read as '$input'. "
          'Did you mean ${options.map((n) => "'$n'").join(' or ')}? Tap a '
          'suggestion only if it matches your prescription.',
      NameStatus.unknown => input.isEmpty ? null : c.warning,
    };
  }

  /// Name only (for older callers).
  static String correct(String name) => check(name).name;

  /// Is the name visible in the OCR text? Catches medications a vision model
  /// invented or replaced. Tolerant because OCR text is noisy.
  static bool foundInText(String name, String text) {
    final first = name.toLowerCase().split(RegExp(r'[^a-z]+')).firstWhere(
          (w) => w.isNotEmpty,
          orElse: () => '',
        );
    if (first.length < 4) return true;
    final maxD = first.length <= 7 ? 2 : 3;
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.length >= 3)
        .any((w) => distance(w, first) <= maxD);
  }

  /// Levenshtein distance (number of single-letter edits).
  static int distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
