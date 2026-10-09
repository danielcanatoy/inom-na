import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/rx_parser.dart';

/// Laging ipinapakita ang nabasa bago gumawa ng reminder.
/// Safety feature ito: ang user ang huling magkukumpirma.
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({super.key, required this.result, required this.rawText});
  final ParseResult result;
  final String rawText;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late final List<Medicine> _meds = [...widget.result.meds];
  // Mga gamot na may ⚠️ na hindi pa nasusuri ng user
  late final Set<String> _toCheck = {...widget.result.warnings.keys};

  void _add() => setState(() => _meds.add(Medicine(
        id: Medicine.newId(),
        name: '',
        times: Medicine.defaultTimes(1),
      )));

  void _save() {
    final valid = _meds.where((m) => m.name.trim().isNotEmpty).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lagyan ng pangalan ang gamot.')));
      return;
    }
    if (_meds.any((m) => _toCheck.contains(m.id))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pakisuri muna ang mga gamot na may ⚠️ bago i-save.')));
      return;
    }
    Navigator.pop(context, valid);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final aiUsed = r.source != RxParser.srcOffline;
    final icon = r.source == RxParser.srcVision
        ? Icons.image_search
        : (aiUsed ? Icons.memory : Icons.rule);
    return Scaffold(
      appBar: AppBar(title: const Text('Tama ba ang nabasa?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Card(
            color: aiUsed ? Colors.green.shade50 : Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, color: aiUsed ? Colors.green.shade800 : Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Binasa ng: ${r.source}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ]),
                if (r.note != null) ...[
                  const SizedBox(height: 6),
                  Text(r.note!),
                ],
                if (r.warnings.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${r.warnings.length} gamot ang may ⚠️. Suriin ang bawat isa sa ibaba.',
                      style: TextStyle(
                          color: Colors.deepOrange.shade900, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 6),
                const Text(
                  '⚠️ Maaaring magkamali ang pagbasa, lalo na sa sulat-kamay. '
                  'Ikumpara sa reseta at ayusin ang mali bago i-save. '
                  'Kung hindi sigurado, itanong sa doktor o pharmacist.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                    'Walang ipinadala sa internet. '
                    '${aiUsed ? 'Sa phone at laptop' : 'Sa phone'} lang ito binasa.',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
          ExpansionTile(
            title: const Text('Text na nabasa sa larawan'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(widget.rawText.isEmpty ? '(wala)' : widget.rawText),
              ),
            ],
          ),
          if (_meds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Walang nakitang gamot. Pindutin ang "Magdagdag" para manual na ilagay.'),
            ),
          for (final m in _meds)
            _MedEditor(
              key: ValueKey(m.id),
              med: m,
              warning: _toCheck.contains(m.id) ? widget.result.warnings[m.id] : null,
              onChecked: () => setState(() => _toCheck.remove(m.id)),
              onRemove: () => setState(() => _meds.remove(m)),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Magdagdag ng gamot'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.alarm_on),
            label: const Text('Tama na, i-set ang paalala'),
          ),
        ),
      ),
    );
  }
}

class _MedEditor extends StatefulWidget {
  const _MedEditor({
    super.key,
    required this.med,
    required this.onRemove,
    this.warning,
    this.onChecked,
  });
  final Medicine med;
  final VoidCallback onRemove;
  final String? warning; // may laman = kailangang suriin ang pangalan
  final VoidCallback? onChecked;

  @override
  State<_MedEditor> createState() => _MedEditorState();
}

class _MedEditorState extends State<_MedEditor> {
  Medicine get m => widget.med;

  Future<void> _editTime(int? index) async {
    final base = index == null ? '08:00' : m.times[index];
    final p = base.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (picked == null) return;
    final s = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (index == null) {
        m.times.add(s);
      } else {
        m.times[index] = s;
      }
      m.times.sort();
    });
  }

  InputDecoration _dec(String label, [String? hint]) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final warn = widget.warning;
    final warnColor = Colors.deepOrange.shade700;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: warn == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: warnColor, width: 2),
            ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (warn != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(warn,
                    style: TextStyle(color: warnColor, fontWeight: FontWeight.bold)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onChecked,
                    icon: const Icon(Icons.check),
                    label: const Text('Nasuri ko na, tama ang pangalan'),
                  ),
                ),
              ]),
            ),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: m.name,
                decoration: warn == null
                    ? _dec('Gamot', 'hal. Amoxicillin')
                    : _dec('Gamot', 'hal. Amoxicillin').copyWith(
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: warnColor, width: 2)),
                        labelStyle: TextStyle(color: warnColor),
                      ),
                onChanged: (v) => m.name = v.trim(),
              ),
            ),
            IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: m.dose,
                decoration: _dec('Dose', '500mg'),
                onChanged: (v) => m.dose = v.trim(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: m.qtyLabel,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Piraso kada inom'),
                onChanged: (v) => m.qtyPerIntake = double.tryParse(v) ?? 1,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: m.days?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _dec('Ilang araw', 'blangko = maintenance'),
                onChanged: (v) => setState(() => m.days = int.tryParse(v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: m.stock?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _dec('Ilang piraso ang nabili', 'optional'),
                onChanged: (v) => m.stock = int.tryParse(v),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: m.instructions,
            decoration: _dec('Bilin', 'hal. pagkatapos kumain'),
            onChanged: (v) => m.instructions = v.trim(),
          ),
          const SizedBox(height: 10),
          Text(
            m.isPrn ? 'Oras: kapag kailangan lang (walang paalala)' : 'Oras ng pag-inom (${m.timesPerDay}x kada araw)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Wrap(spacing: 6, children: [
            for (var i = 0; i < m.times.length; i++)
              InputChip(
                label: Text(m.times[i]),
                onPressed: () => _editTime(i),
                onDeleted: () => setState(() => m.times.removeAt(i)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Oras'),
              onPressed: () => _editTime(null),
            ),
          ]),
          if (m.totalDoses != null && m.totalDoses! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Kabuuan: ${m.totalDoses} na dose. Tapusin kahit gumaan na ang pakiramdam.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
