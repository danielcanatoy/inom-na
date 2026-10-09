/// One recognized text line and its position on the photo (pixels).
class OcrLine {
  const OcrLine(this.text,
      {required this.top, required this.bottom, required this.left});
  final String text;
  final double top;
  final double bottom;
  final double left;
  double get center => (top + bottom) / 2;
  double get height => bottom - top;
}

/// Rebuilds reading order from line positions: lines whose vertical centers
/// fall within half a line height form one visual row (e.g. a medicine name
/// and the strength printed beside it), rows go top to bottom and lines in
/// a row go left to right. Text itself is never changed.
class OcrLayout {
  static String arrange(List<OcrLine> lines) {
    final usable = [
      for (final line in lines)
        if (line.text.trim().isNotEmpty && line.height > 0) line
    ]..sort((a, b) => a.center.compareTo(b.center));
    if (usable.isEmpty) return '';
    final heights = usable.map((l) => l.height).toList()..sort();
    final tolerance = heights[heights.length ~/ 2] / 2;
    final rows = <List<OcrLine>>[];
    for (final line in usable) {
      final row = rows.isEmpty ? null : rows.last;
      final rowCenter = row == null
          ? null
          : row.map((l) => l.center).reduce((a, b) => a + b) / row.length;
      if (row != null && (line.center - rowCenter!).abs() <= tolerance) {
        row.add(line);
      } else {
        rows.add([line]);
      }
    }
    return [
      for (final row in rows)
        (row..sort((a, b) => a.left.compareTo(b.left)))
            .map((l) => l.text.trim())
            .join('  ')
    ].join('\n');
  }
}
