import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/store.dart';

Medicine medicine({String id = 'demo-med', String name = 'Losartan'}) => Medicine(
      id: id,
      name: name,
      dose: '50mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: 1,
      times: ['08:00'],
      durationConfirmed: true,
      days: 7,
      start: DateTime(2026, 10, 9),
    );

Future<SharedPreferences> initialize(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  await Store.init();
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initialize({});
  });

  test('legacy medicine data is readable and exact original blob is backed up', () async {
    final legacy = jsonEncode([
      {
        'id': 'legacy-demo', 'name': 'Losartan', 'dose': '50mg',
        'qtyPerIntake': 1, 'times': ['08:00'], 'days': null,
        'start': '2026-10-09T00:00:00.000', 'taken': ['2026-10-09 08:00'],
      },
    ]);
    final preferences = await initialize({'meds': legacy});
    final records = Store.meds();
    expect(records.single.legacy, isTrue);
    expect(records.single.taken, ['2026-10-09 08:00']);
    expect(records.single.isMaintenance, isTrue);
    await Store.saveMeds(records);
    expect(preferences.getString('meds_phase1_backup'), legacy);
    expect(Store.meds().single.taken, ['2026-10-09 08:00']);
    expect((jsonDecode(preferences.getString('meds')!) as List).single['schemaVersion'], 2);
  });

  test('existing backup is never replaced by subsequent edits', () async {
    const originalBackup = 'original synthetic backup';
    final preferences = await initialize({
      'meds': jsonEncode([medicine().toJson()]),
      'meds_phase1_backup': originalBackup,
    });
    Store.meds();
    await Store.saveMeds([medicine(name: 'Metformin')]);
    expect(preferences.getString('meds_phase1_backup'), originalBackup);
  });

  test('corrupt JSON stays intact and blocks destructive replacement', () async {
    const original = '{unfinished synthetic JSON';
    final preferences = await initialize({'meds': original});
    expect(Store.meds(), isEmpty);
    expect(Store.loadError, isNotNull);
    await expectLater(Store.saveMeds([medicine()]), throwsStateError);
    expect(preferences.getString('meds'), original);
  });

  test('corrupt JSON cannot be overwritten before records are loaded', () async {
    const original = '{unfinished synthetic JSON';
    final preferences = await initialize({'meds': original});
    expect(Store.loadError, isNull);
    await expectLater(Store.saveMeds([medicine()]), throwsStateError);
    expect(preferences.getString('meds'), original);
  });

  test('invalid stored record stays intact', () async {
    final original = jsonEncode([{'id': 'demo', 'name': 'Losartan', 'start': 'invalid'}]);
    final preferences = await initialize({'meds': original});
    expect(Store.meds(), isEmpty);
    expect(Store.loadError, isNotNull);
    await expectLater(Store.saveMeds([]), throwsStateError);
    expect(preferences.getString('meds'), original);
  });

  test('duplicate IDs in existing storage trigger recovery guard', () async {
    final original = jsonEncode([medicine().toJson(), medicine().toJson()]);
    final preferences = await initialize({'meds': original});
    expect(Store.meds(), isEmpty);
    expect(Store.loadError, isNotNull);
    await expectLater(Store.saveMeds([medicine()]), throwsStateError);
    expect(preferences.getString('meds'), original);
  });

  test('duplicate IDs in proposed save are refused without changing existing data', () async {
    final original = jsonEncode([medicine().toJson()]);
    final preferences = await initialize({'meds': original});
    Store.meds();
    await expectLater(Store.saveMeds([medicine(), medicine()]), throwsStateError);
    expect(preferences.getString('meds'), original);
    expect(preferences.getString('meds_phase1_backup'), isNull);
  });

  test('queued writes capture snapshots before later object mutations', () async {
    final preferences = await initialize({});
    final record = medicine(name: 'First snapshot');
    final first = Store.saveMeds([record]);
    record.name = 'Second snapshot';
    final second = Store.saveMeds([record]);
    record.name = 'Unsaved mutation';
    await Future.wait([first, second]);
    expect(Store.meds().single.name, 'Second snapshot');
    final backup = jsonDecode(preferences.getString('meds_phase1_backup')!) as List;
    expect(backup.single['name'], 'First snapshot');
  });

  test('rejected save does not poison later queued writes', () async {
    await expectLater(Store.saveMeds([medicine(), medicine()]), throwsStateError);
    await Store.saveMeds([medicine()]);
    expect(Store.meds().single.id, 'demo-med');
  });

  test('local laptop and loopback endpoints are accepted', () {
    for (final endpoint in [
      'http://192.168.1.81:11434', 'http://10.0.0.2:11434',
      'http://172.16.0.2:11434', 'http://172.31.255.254:11434',
      'http://169.254.10.20:11434', 'http://127.0.0.1:11434',
      'http://localhost:11434', 'http://[::1]:11434',
      'http://[fc00::1]:11434',
    ]) {
      expect(() => Store.localOllamaUri(endpoint), returnsNormally);
    }
  });

  test('trailing slash is normalized for Ollama API resolution', () {
    final endpoint = Store.localOllamaUri(' http://192.168.1.81:11434/ ');
    expect(endpoint.resolve('/api/chat').toString(), 'http://192.168.1.81:11434/api/chat');
  });

  test('public IPs and DNS hostnames are refused', () {
    for (final endpoint in [
      'https://example.com', 'http://8.8.8.8:11434',
      'http://172.15.0.2:11434', 'http://172.32.0.2:11434',
      'http://[2001:4860:4860::8888]:11434',
    ]) {
      expect(() => Store.localOllamaUri(endpoint), throwsFormatException);
    }
  });

  test('credentials, query, fragment, path and unsupported schemes are refused', () {
    for (final endpoint in [
      'http://user:example@192.168.1.81:11434',
      'http://192.168.1.81:11434?key=example',
      'http://192.168.1.81:11434#section',
      'http://192.168.1.81:11434/api/chat',
      'file://192.168.1.81', '192.168.1.81:11434',
    ]) {
      expect(() => Store.localOllamaUri(endpoint), throwsFormatException);
    }
  });

  test('public endpoint rejection preserves previous AI settings', () async {
    await Store.setOllama('http://192.168.1.81:11434', 'qwen2.5:3b', 'qwen2.5vl:3b');
    await expectLater(Store.setOllama('https://example.com', 'qwen2.5:3b', 'qwen2.5vl:3b'), throwsFormatException);
    expect(Store.ollamaUrl, 'http://192.168.1.81:11434');
  });

  test('cloud-tagged models cannot be configured', () async {
    for (final model in ['qwen:cloud', 'qwen-cloud', 'qwen-cloud:latest', 'cloud', 'namespace/cloud']) {
      await expectLater(Store.setOllama('http://192.168.1.81:11434', model, ''), throwsFormatException);
      await expectLater(Store.setOllama('http://192.168.1.81:11434', 'qwen2.5:3b', model), throwsFormatException);
    }
  });

  test('local settings are persisted and blank text models are refused', () async {
    final preferences = await initialize({});
    await Store.setOllama('http://10.0.0.2:11434/', ' qwen2.5:3b ', ' qwen2.5vl:3b ');
    expect(preferences.getString('ollamaUrl'), 'http://10.0.0.2:11434');
    expect(Store.ollamaModel, 'qwen2.5:3b');
    expect(Store.visionModel, 'qwen2.5vl:3b');
    await expectLater(Store.setOllama('http://10.0.0.2:11434', ' ', ''), throwsFormatException);
  });
}
