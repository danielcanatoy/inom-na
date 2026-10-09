enum NameStatus { known, corrected, uncertain, unknown }

class NameCheck {
  NameCheck(this.name, this.status, this.warning);
  final String name; // pangalang gagamitin (orihinal kung hindi sigurado)
  final NameStatus status;
  final String? warning; // null = walang kailangang suriin
}

/// Listahan ng karaniwang gamot sa Pilipinas + auto-correct ng maling basa
/// (hal. "Amoxicilin" -> "Amoxicillin"). Offline, tumatakbo sa phone.
/// Ang user pa rin ang huling magkukumpirma sa ConfirmScreen.
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
    // Puso / presyon
    'Losartan', 'Amlodipine', 'Metoprolol', 'Atenolol', 'Carvedilol',
    'Bisoprolol', 'Captopril', 'Enalapril', 'Lisinopril', 'Telmisartan',
    'Valsartan', 'Hydrochlorothiazide', 'Furosemide', 'Spironolactone',
    'Felodipine', 'Nifedipine', 'Clopidogrel', 'Isosorbide Mononitrate',
    'Trimetazidine', 'Digoxin', 'Warfarin',
    // Diabetes / cholesterol
    'Metformin', 'Gliclazide', 'Glimepiride', 'Sitagliptin',
    'Atorvastatin', 'Rosuvastatin', 'Simvastatin',
    // Sikmura
    'Omeprazole', 'Pantoprazole', 'Esomeprazole', 'Famotidine',
    'Domperidone', 'Metoclopramide', 'Loperamide', 'Hyoscine',
    // Allergy / ubo / hika
    'Cetirizine', 'Loratadine', 'Diphenhydramine', 'Chlorphenamine',
    'Salbutamol', 'Montelukast', 'Ambroxol', 'Carbocisteine',
    'Guaifenesin', 'Lagundi', 'Sambong',
    // Iba pa
    'Prednisone', 'Prednisolone', 'Dexamethasone', 'Methylprednisolone',
    'Allopurinol',
    'Colchicine', 'Levothyroxine', 'Ferrous Sulfate', 'Folic Acid',
    'Ascorbic Acid', 'Calcium Carbonate', 'Betahistine', 'Cinnarizine',
    'Mebendazole', 'Albendazole', 'Isoniazid', 'Rifampicin', 'Ethambutol',
    'Pyrazinamide', 'Oseltamivir', 'Acyclovir', 'Fluconazole', 'Tamsulosin',
    'Gabapentin', 'Pregabalin', 'Sertraline', 'Fluoxetine',
  ];

  /// Sinusuri ang nabasang pangalan. SAFETY: maliit na typo lang ang inaayos
  /// (max 1 letra kung 5–9 letra, max 2 kung 10+; walang auto-correct kung <5).
  /// Kapag malabo, malayo, o may kahawig na ibang gamot: hindi binabago, may babala.
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
        secondD > bestD + 1; // walang ibang gamot na halos kasing-lapit
    final sameStart = lower[0] == best[0].toLowerCase();
    if (bestD <= maxD && clearWinner && sameStart) {
      return NameCheck(best, NameStatus.corrected,
          "⚠️ Nabasa: '$input' → ginawang '$best'. Pakisuri.");
    }

    final near = [
      for (final r in ranked)
        if (r.$1 <= maxD + 1) r.$2
    ].take(2).toList();
    if (near.isNotEmpty) {
      return NameCheck(
          input,
          NameStatus.uncertain,
          "⚠️ Nabasa: '$input'. Hindi sigurado: baka ${near.map((n) => "'$n'").join(' o ')}? "
          'Pakisuri sa reseta.');
    }
    return NameCheck(input, NameStatus.unknown,
        "⚠️ Wala sa listahan ng app ang '$input'. Pakisuri ang spelling sa reseta.");
  }

  /// Pangalan lang (para sa lumang code).
  static String correct(String name) => check(name).name;

  /// Nakikita ba ang pangalan sa OCR text? Pang-check kung inimbento o pinalitan
  /// ng vision model ang gamot. Maluwag ang tolerance dahil magulo ang OCR.
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

  /// Levenshtein distance (ilang letra ang kailangang palitan).
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
