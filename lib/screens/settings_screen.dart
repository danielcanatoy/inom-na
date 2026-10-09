import 'package:flutter/material.dart';

import '../services/rx_parser.dart';
import '../services/scheduler.dart';
import '../services/store.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../ui/brand.dart';
import '../ui/components.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController(text: Store.ollamaUrl);
  final _model = TextEditingController(text: Store.ollamaModel);
  final _vision = TextEditingController(text: Store.visionModel);
  String? _status;
  bool _connected = false;
  bool _busy = false;
  SchedulerPermissionStatus? _permissions;
  bool _permissionsChecked = false;
  String? _reminderResult;
  bool _reminderBusy = false;
  bool _followEnabled = Store.followUpEnabled;
  int _followMinutes = Store.followUpMinutes;

  Future<void> _setFollowUp({bool? enabled, int? minutes}) async {
    final nextEnabled = enabled ?? _followEnabled;
    final nextMinutes = minutes ?? _followMinutes;
    setState(() => _reminderBusy = true);
    try {
      await Store.setFollowUp(enabled: nextEnabled, minutes: nextMinutes);
      setState(() {
        _followEnabled = nextEnabled;
        _followMinutes = nextMinutes;
      });
      // Reconcile now so follow-ups are added or removed immediately.
      final result = await Scheduler.rescheduleAll(Store.meds());
      if (mounted) {
        setState(() => _reminderResult = result.success
            ? result.message ??
                (nextEnabled
                    ? 'Follow-up reminders are on ($nextMinutes minutes).'
                    : 'Follow-up reminders are off.')
            : result.message ?? 'Reminders could not be updated.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _reminderResult = 'The follow-up setting could not be saved.');
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    SchedulerPermissionStatus? status;
    try {
      status = await Scheduler.permissionStatus()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      status = null; // Shown as "Could not check", never guessed.
    }
    if (mounted) {
      setState(() {
        _permissions = status;
        _permissionsChecked = true;
      });
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await Store.setOllama(_url.text, _model.text, _vision.text);
      final s = await RxParser.ping();
      if (mounted) {
        setState(() {
          _status = s;
          _connected = s.startsWith(RxParser.pingConnected);
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message.toString();
          _connected = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'The AI connection settings could not be saved or tested.';
          _connected = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _reminderBusy = true);
    try {
      await Scheduler.requestPermissions().timeout(const Duration(seconds: 30));
    } catch (_) {
      // The status below is re-read either way.
    }
    await _loadPermissions();
    if (mounted) setState(() => _reminderBusy = false);
  }

  Future<void> _sendTest() async {
    setState(() => _reminderBusy = true);
    try {
      await Scheduler.requestPermissions();
      final result = await Scheduler.testInOneMinute(null);
      await _loadPermissions();
      if (mounted) {
        setState(() => _reminderResult = result.success
            ? result.message ??
                'Test reminder set. It should appear in about 1 minute.'
            : result.message ?? 'The test reminder could not be set.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _reminderResult =
            'The test reminder could not be set. Check Android settings.');
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _vision.dispose();
    super.dispose();
  }

  Widget _permissionRow(String label, bool? granted, String deniedHint) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label, style: textTheme.bodyLarge),
            !_permissionsChecked
                ? const StatusBadge(
                    label: 'Checking…', tone: Tone.info, icon: Icons.sync)
                : granted == null
                    ? const StatusBadge(
                        label: 'Could not check', tone: Tone.warning)
                    : granted
                        ? const StatusBadge(
                            label: 'Allowed', tone: Tone.success)
                        : const StatusBadge(
                            label: 'Not allowed', tone: Tone.error),
          ],
        ),
        if (granted == false)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(deniedHint, style: textTheme.bodySmall),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            // ---- AI connection ----
            const SectionHeader('AI Connection',
                icon: Icons.laptop_chromebook_outlined,
                subtitle: 'Ollama running on your laptop'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'IMedsU can use an Ollama AI server on your laptop to read '
                          'prescriptions. Connect this phone and the laptop to the '
                          'same Wi-Fi or hotspot. No internet is needed.',
                          style: textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Ollama server address',
                          hintText: 'http://192.168.1.10:11434',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _model,
                        decoration: const InputDecoration(
                          labelText: 'Text model',
                          hintText: 'qwen2.5:3b',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _vision,
                        decoration: const InputDecoration(
                          labelText: 'Vision model (best for handwriting)',
                          hintText: 'qwen2.5vl:3b',
                          helperText:
                              'Leave blank to skip reading photos with AI.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _test,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.wifi_tethering),
                          label: Text(
                              _busy ? 'Testing…' : 'Save and Test Connection'),
                        ),
                      ),
                      if (_status != null)
                        InfoBanner(
                          tone: _connected ? Tone.success : Tone.error,
                          title: _connected ? 'Connected' : 'Not connected',
                          message: _status!.startsWith(RxParser.pingConnected)
                              ? _status!
                                  .substring(RxParser.pingConnected.length)
                                  .trim()
                              : _status,
                        ),
                      const SizedBox(height: 4),
                      Text(
                          'If the laptop AI cannot be reached, IMedsU still works '
                          'using the offline reader on this phone.',
                          style: textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Laptop setup and privacy'),
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '1. On the laptop, start Ollama so the phone can '
                                'reach it:\n   OLLAMA_HOST=0.0.0.0 ollama serve\n'
                                '2. Find the laptop IP address (ipconfig on Windows).\n'
                                '3. Enter http://<laptop IP>:11434 above and test.\n\n'
                                'Privacy: the prescription photo and the text read '
                                'from it are sent to this laptop over your local '
                                'network. The HTTP connection is not encrypted, so use '
                                'a trusted Wi-Fi or hotspot. Only local network '
                                'addresses and local models are allowed.',
                                style: textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ]),
              ),
            ),

            // ---- Notifications ----
            const SectionHeader('Notifications',
                icon: Icons.notifications_outlined,
                subtitle: 'Medication reminders on this phone'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _permissionRow(
                          'Notifications',
                          _permissions?.notificationsGranted,
                          'Reminders cannot appear. Allow notifications for IMedsU.'),
                      _permissionRow(
                          'Alarms & reminders (exact timing)',
                          _permissions?.exactAlarmsGranted,
                          'Reminders may arrive late. Allow "Alarms & reminders" '
                              'for IMedsU.'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                            onPressed:
                                _reminderBusy ? null : _requestPermissions,
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('Request Permissions')),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _reminderBusy ? null : _sendTest,
                            icon:
                                const Icon(Icons.notifications_active_outlined),
                            label: const Text(AppStrings.sendTestReminder)),
                      ),
                      const Divider(height: 32),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _followEnabled,
                        onChanged: _reminderBusy
                            ? null
                            : (value) => _setFollowUp(enabled: value),
                        title: Text('Follow-Up Reminders',
                            style: textTheme.titleMedium),
                        subtitle: const Text(
                            "Remind me again if I haven't marked my "
                            'medication as taken. On by default, 30 minutes after '
                            'the scheduled time.'),
                      ),
                      if (_followEnabled) ...[
                        Text('Remind me again after',
                            style: textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        SegmentedButton<int>(
                          segments: [
                            for (final minutes in Store.followUpChoices)
                              ButtonSegment(
                                  value: minutes, label: Text('$minutes min')),
                          ],
                          selected: {_followMinutes},
                          onSelectionChanged: _reminderBusy
                              ? null
                              : (value) => _setFollowUp(minutes: value.first),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                          'A follow-up is about the same dose, not an extra dose. It '
                          'is cancelled when you mark the dose as taken. Each dose '
                          'gets at most one follow-up.',
                          style: textTheme.bodySmall),
                      if (_reminderResult != null)
                        InfoBanner(tone: Tone.info, message: _reminderResult),
                      const SizedBox(height: 8),
                      Text(
                          'On Xiaomi, Redmi and POCO phones (HyperOS/MIUI): open '
                          'App info for IMedsU, turn Autostart on, and set Battery '
                          'saver to "No restrictions". Otherwise reminders may not '
                          'appear while the app is closed.',
                          style: textTheme.bodySmall),
                    ]),
              ),
            ),

            // ---- About ----
            const SectionHeader('About', icon: Icons.info_outline),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IMedsULogo(fontSize: 30),
                      const SizedBox(height: 6),
                      Text(AppStrings.tagline,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.primaryDark)),
                      const SizedBox(height: 4),
                      Text('Version 1.0.0', style: textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Text(
                          'Text recognition: Google ML Kit, on this phone.\n'
                          'Prescription AI: Ollama (qwen2.5 models) on your laptop, '
                          'over your local network.\n'
                          'Offline reader: rule-based, on this phone.\n'
                          'Medications and reminders are stored on this phone.',
                          style: textTheme.bodyMedium),
                      const InfoBanner(
                          tone: Tone.info,
                          title: 'Not medical advice',
                          message: AppStrings.disclaimer),
                    ]),
              ),
            ),
          ]),
    );
  }
}
