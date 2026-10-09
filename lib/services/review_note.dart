/// Review-note categories. Parsers decide whether a schedule must stay
/// unresolved by checking these prefixes, so wording changes cannot silently
/// change parsing behavior.
class ReviewNote {
  static const conflict = 'Conflict:';
  static const mismatch = 'Mismatch:';
  static const invalid = 'Invalid:';
  static const unclear = 'Unclear:';

  static const durationConflict =
      '$conflict the treatment duration is contradictory.';

  /// Conflicting or unclear directions (used when comparing AI with OCR).
  static bool isConflictOrUnclear(String note) =>
      note.startsWith(conflict) || note.startsWith(unclear);

  /// Any note that means the written schedule cannot be trusted as-is.
  static bool blocksSchedule(String note) =>
      isConflictOrUnclear(note) ||
      note.startsWith(mismatch) ||
      note.startsWith(invalid);

  static bool isDurationConflict(String note) => note == durationConflict;
}
