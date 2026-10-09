# Phase 1 implementation and verification record

## Baseline and checkpoint

- Initial Git status: clean `main`; no modified or untracked files.
- Baseline commit: `909f6e7` (`Inom Na! hackathon build`).
- Local checkpoint branch: `checkpoint/inomna-phase1-20261009`, pointing to the baseline commit. No new commit, push or merge was performed.
- Initial targeted credential checks found no matches. No credentials, generated build artifacts or local configuration were added to Git.
- Flutter, Dart and ADB were unavailable on this laptop. The user confirmed Flutter/Dart are installed on another laptop and requested no installation or further SDK searching.
- Baseline analysis/tests could not run. No pre-existing source-test failures can therefore be claimed or ruled out. The unchanged lockfile requires Dart >=3.12 / Flutter >=3.44; use a compatible SDK on the other laptop.

## Files changed

Production: `lib/models/medicine.dart`, `lib/screens/confirm_screen.dart`, `lib/screens/home_screen.dart`, `lib/screens/settings_screen.dart`, `lib/services/fallback_parser.dart`, `lib/services/rx_parser.dart`, `lib/services/store.dart`, `lib/services/scheduler.dart`, new `lib/services/reminder_plan.dart`, and `android/app/src/main/kotlin/com/inomna/inom_na/MainActivity.kt`.

Tests: updated `test/fallback_parser_test.dart` and `test/med_names_test.dart`; added `test/medicine_test.dart`, `test/rx_parser_test.dart`, `test/store_test.dart`, `test/confirm_screen_test.dart`, `test/reminder_plan_test.dart`, and `test/scheduler_test.dart`.

Documentation: `README.md` and this report. Dependencies, lockfile and AndroidManifest permissions are unchanged.

## Fixes

- Unknown frequency, missing duration, invalid dosage and missing/invalid quantity remain unresolved. Maintenance and PRN require explicit prescription meaning. Every medicine requires whole-prescription verification; edits invalidate verification and saving revalidates fields. Original OCR text and uncertain directions remain available for review.
- Daily counts, prescribed clock times and fixed intervals have distinct schedule kinds. q6h/q8h generate equal intervals from a reviewed first-dose anchor. Conflicting clock anchors cannot be confirmed; OCR mistakes can be corrected. Duplicate/invalid times and contradictory dates are blocked. End bounds are exclusive and respected by generation; a prescribed calendar end date includes its final day. Saving no longer replaces the reviewed start with the current time.
- Planned completion and all scheduled doses taken are separate states. Taken records are idempotent scheduled-dose keys; historical actual intake timestamps are never invented.
- UI/storage/reminder updates serialize and capture snapshots. Medicine/dose identities are stable. Checklist actions cancel only the affected dose or recurring series; reconciliation skips unchanged pending reminders. IDs, registration metadata and failed-cancellation tombstones persist. Failed registration attempts preserve/restore old reminders where possible and report incomplete recovery.
- Notification permission failures and exact-alarm restrictions produce explicit results. Inexact fallback warns of possible delay. Medication data can be saved even if registration fails, with a persistent warning and retry action instead of a false success message.
- Whole finite courses register or fail explicitly above the application budget of 400 pending reminders. Daily and q6h/q8h maintenance schedules use recurring series. A small Android bridge uses the pinned notification plugin's native daily-repeat support to honor the first date, including tomorrow after marking a dose early. This bridge is uncompiled and needs device verification.
- Raw prescription/AI response/error logging was removed. Privacy text now discloses image/OCR transmission to the local laptop and unencrypted HTTP. Inference revalidates local endpoints and rejects cloud-tagged models; no cloud service was introduced.
- Old medication blobs are read without fabricating missing historical data. The exact original blob is backed up to `meds_phase1_backup` before the first update. Corrupt records and duplicate medicine IDs prevent destructive replacement.

## Exact verification results

- `flutter analyze --no-pub`: exit 1; command could not start because `flutter` was not recognized. No Dart analysis occurred.
- `flutter test --no-pub`: exit 1; same missing-command failure. Zero tests executed; no passing/failing test result is available.
- Source-level local-import check: 42 relative/project Dart imports resolved; zero missing files.
- Source-level logging/cancellation check: zero production `print`/`debugPrint` calls and zero `cancelAll` calls.
- `git diff --check`: final exit 0, no whitespace errors. Extra EOF blank lines on the two replaced screens were corrected. Git emitted only an LF/CRLF advisory.
- `git diff --exit-code -- pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml`: exit 0; unchanged.
- Authored inventory: 129 cases across eight test files (28 model, 23 fallback, 20 Rx conversion, 10 name/JSON, 16 persistence, 6 confirmation widgets, 7 reminder planner, 19 scheduler/native-channel). These are authored counts, not executed results.

## Verification on the Flutter laptop

Use this updated checkout, including the native Android file; copying only `lib/` will omit the bridge. Run from the repository root:

```powershell
flutter --version
flutter doctor -v
flutter pub get --enforce-lockfile
dart format lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
flutter devices
flutter run --no-pub -d <ANDROID_DEVICE_ID>
```

Replace the device placeholder with the ID from `flutter devices`. Do not run dependency upgrades. If dependency resolution fails, verify the SDK against the existing lockfile first.

On a real Android device, verify: scanned/typed prescription -> corrections -> verification -> saved data -> notification; q8h equal intervals and explicit clock preservation; future starts and final-dose boundaries; PRN with no scheduled reminders; marking a future dose early suppresses that occurrence and retains tomorrow's recurring reminder; undo restores the correct occurrence; overlapping medicines remain independent; permission denial and exact-alarm revocation produce truthful warnings; retry works; registration/cancellation failures preserve data; reminders deliver with the app closed, under Doze/battery restrictions and after reboot; old saved records survive update and restart. Test camera/OCR and Ollama vision -> text -> phone-only fallback using synthetic prescriptions.

## Limitations and compatibility

- Dart/Flutter compilation, static analysis, all automated tests, Android native compilation, actual delivery, reboot recovery and OCR/AI accuracy are **not verified** here.
- The native bridge and its internal Dart serializer depend on pinned `flutter_local_notifications` v17 behavior. Compile it before accepting reminder reliability or changing that dependency.
- Indefinite intervals that do not divide 24 hours fail explicitly. They do not silently become daily or stop after a hidden horizon. Scheduling more than 400 pending reminders also fails explicitly; the app must never suggest shortening a prescription to meet its limit.
- Manila is still the reminder timezone. Travel, timezone/clock changes and other platforms are not validated in this phase.
- New dosage validation expects a positive numeric value with a recognized unit. Unusual dosage formats require explicit correction; unsupported forms need later validation support.
- Legacy schedules retain their original clock times/course counts; previously guessed frequencies or durations cannot be reconstructed automatically. Existing-record editing and retrospective prescription re-verification are outside this phase.
- SharedPreferences remains local, unencrypted application storage. A trusted LAN/local Ollama server is required; the app cannot attest to operator changes inside that server or custom model behavior.
- The schema is backward-readable by this version. Downgrading to the original application can lose new interval semantics because the original code does not understand these fields. Preserve backups and handle new records before downgrading.
- No Routine ko, chatbot, full-screen alarms, follow-ups or Phase 2 development was added. Proceed to later reminder/routine enhancements only after analyzer/tests, Android build and the core real-device checks succeed and the user approves.
