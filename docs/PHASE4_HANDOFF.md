# IMedsU — Phase 4 Development Handoff

_Prepared October 10, 2026 (Asia/Manila). Synthetic data only; no real patient information._

## 1. Snapshot

| Item | State |
|---|---|
| Branch | `phase4-reminders-tracking` (not pushed or merged by Claude) |
| Latest commit | `3589f87 "Cropped Image Feature"` |
| Uncommitted changes | **None** before this handoff. This handoff adds `docs/PHASE4_HANDOFF.md` and edits `Claude.md` (both uncommitted) |
| Automated tests | **321 passed, 0 failed, 0 skipped** (`flutter test --reporter expanded`, last run on the final scanner investigation). The often-quoted "314" was the run *before* the 7 device-evidence tests were added |
| Analyzer | 0 errors, 0 warnings, **18 pre-existing info lints** (`flutter analyze` still exits 1 because of them) |
| APK | `flutter build apk --debug` ✅; installed on the Poco X7 Pro with `adb install -r` (data kept) |
| Toolchain | Flutter 3.47.7 / Dart 3.13.5 at `C:\dev\flutter`; `flutter_local_notifications` pinned at **17.2.4** |

**The commit name is misleading:** `3589f87` contains the Scan details view, the debug-only OCR probe and the parser fixes. **No image cropping or enhancement code exists yet** (`grep -ri crop lib/` finds nothing).

## 2. Architecture (current)

```text
Camera / gallery (image_picker, 2400 px, JPEG 95) or typed text
 ├─ Phone Only (DEFAULT): ML Kit OCR on phone (bundled model, offline)
 │     → OcrLayout reading order (rows top→bottom, left→right; raw ML Kit text kept as fallback)
 │     → FallbackParser (rule-based Dart, NOT an AI model)
 └─ Enhanced AI (opt-in, Settings → Prescription Reading): laptop Ollama over LAN
       qwen2.5vl:3b (photo + OCR hint) → qwen2.5:3b (OCR text) → disclosed fallback to the phone reader
 → MedNames suggestions (never auto-applied) + StrengthCheck flags
 → Review Prescription: compact cards, Edit Details, Verify Medication (dialog), Scan details
 → Store (SharedPreferences) + ReminderPlan/ReminderCoordinator → flutter_local_notifications + Kotlin daily bridge
 → Home / Calendar / Medications tabs; Settings (reading mode, daily routine, notifications, Ollama)
```

Key services: `rx_parser.dart` (pipeline, `ScanControl` cancellation, counts-only diagnostics), `fallback_parser.dart`, `ocr.dart` + `ocr_layout.dart`, `med_names.dart`, `strength_check.dart`, `schedule_edit.dart`, `dose_status.dart`, `routine_schedule.dart`, `reminder_plan.dart`, `scheduler.dart`, `store.dart`, `ocr_probe.dart` (debug only).

## 3. Completed phases

1. **Phase 1:** medication safety validation (no guessed frequency or duration), exact q6h/q8h intervals, explicit times, stable reminder IDs, targeted cancellation, legacy record compatibility.
2. **Phase 2:** IMedsU rebrand, English UI, Material 3 design system, logo and launcher icon, responsive layouts.
3. **Phase 3:** My Daily Routine, routine-based suggestions (meal offsets never assumed), Edit Schedule with history-preserving revisions; finite courses keep their dose count.
4. **Phase 4:**
   - Follow-up reminders: on by default, 10/30/60 min, one per dose, cancelled when taken.
   - Statuses: Upcoming / Taken / Overdue / Missed (2 h).
   - Intake history: `takenAt`; legacy records keep "time not recorded".
   - Weekly calendar with Jump to Date.
   - Bottom navigation.
   - Compact review screen.
   - Edit Medication, with the original text kept as `sourceText`.
   - Today rule: same-day edits must keep the exact daily dose count.
   - Cancelable scans.
   - Phone Only as the default mode.
   - OCR-tolerant parsing with flags.
   - Strength checks.
   - Scan details view.

## 4. Verified on the Poco X7 Pro vs. not yet

**Observed on the device:**
- The APK installs over the old app and keeps data.
- Home and the bottom navigation render, and saved medicines load.
- No crashes in logcat.
- Native alarms are registered (`adb shell dumpsys alarm`): exact 8:00 alarms plus 8:30 follow-ups, no follow-up for a dose already taken, and no duplicates after reinstalling.
- Real ML Kit OCR on **synthetic printed** images (via the debug probe): clean print is read almost perfectly, at about 70–180 ms per image.
- The user reported: Phone Only scanning runs without the laptop, Enhanced AI with Ollama reads their prescription better, and Phone Only still fails on their own prescription.

**Not yet observed:**
- Notification delivery with the app closed, the phone locked, under Doze, or after reboot.
- A full follow-up sequence.
- The calendar, editing and review interactions on the device (HyperOS blocks `adb` input, so these need manual testing).
- Phone Only accuracy on the user's real prescription. Claude must not view it (see section 9).
- Any handwriting.

## 5. Phone-only OCR and parser limitations (evidence-based)

- **ML Kit's raw order scrambles multi-column layouts.** The reordering in `OcrLayout` fixes the measured cases (table columns, clinic headers).
- **Observed ML Kit misreads:** `Amoxicilin`, `I tab` (read as "1 tab" and flagged), `15 mg/5 m` (left incomplete, not guessed), `SAMPLEI`.
- **The rule parser handles printed formats only:** strength patterns, "Medicine:" labels, word frequencies, q6h/q8h, PRN, "x N days", "ongoing", quantity labels. It doesn't handle handwriting, free-form sentences, or medicines that aren't in the app's ~90-name list. Unknown names are kept as read, with no suggestion.
- **Resolution:** downscaling to 1000 px gave mixed results; there's no evidence that larger images help.
- **Benchmark:** the synthetic set went from 45/72 to 72/72 fields; the held-out set scored 24/24 both before and after. Real-photo accuracy is unmeasured.

## 6. Optional laptop Ollama

- It's still in the app as **Enhanced AI** (opt-in), with models `qwen2.5:3b` and `qwen2.5vl:3b`. Ollama must run with `OLLAMA_HOST=0.0.0.0` on the same Wi-Fi or hotspot.
- If it's unreachable, the app falls back to the phone reader, says so, and never blocks scanning.
- Only local or private network addresses are accepted, and cloud-tagged models are refused.

## 7. Latest decision (October 10, 2026), not yet started

1. The **phone must work independently of the laptop.**
2. The goal is better recognition of **readable handwritten** prescriptions.
3. **First:** investigate on-device **document cropping and enhancement** (crop to the page, deskew, contrast) before OCR. Measure it against the current pipeline with synthetic samples, using the debug probe or the Scan details view.
4. **Separately**, consider an experimental on-device vision model (for example **Gemma 3n**) in a **separate spike branch or prototype**. Measure accuracy, latency, memory and APK size on the Poco X7 Pro (16 GB RAM, Dimensity 8400-Ultra).
5. **Preserve** the working scanner, reminders, calendar and medication verification.
6. **Do not integrate an experimental model into the stable app without testing.** No silent auto-correction of names, strengths or frequencies; mandatory review stays.

## 8. Outstanding issues and proposed next steps

1. Manual phone tests:
   - A Phone Only scan of a printed synthetic sample, checked against the Scan details view.
   - A notification with the app closed.
   - One full follow-up.
   - The calendar's Jump to Date and the tabs, with Android Back.
   - Edit Medication and the Today rule.
2. Cropping and enhancement spike (section 7.3), with before/after OCR numbers.
3. An optional Gemma 3n spike in a separate branch (section 7.4). Feed the evidence into a go/no-go decision.
4. Clean up the synthetic probe images left on the phone: `adb shell rm -r /data/local/tmp/ocr_probe`, plus the app's `cache/ocr_probe` folder via `run-as`.
5. Phase 5: final testing, README accuracy table (real results only), disclosures, demo preparation and submission.
6. Known gaps:
   - One invalid medicine record blocks reminders for all medicines.
   - The 18 info lints.
   - Reminder delivery on HyperOS is unproven.
   - Finite-course follow-ups only cover the next 7 days.

## 9. Resuming safely

1. Read `Claude.md`, then this file. Run `git status` and `git log --oneline -5`. **Do not reset, discard, push or merge**, and commit only when asked.
2. Environment (PowerShell): `$env:Path = "C:\dev\flutter\bin;$env:Path"`. Verify with `flutter --version` and `flutter pub get --enforce-lockfile`.
3. Baseline: `dart format lib test tool` → `flutter analyze --no-pub` (expect 18 infos) → `flutter test --no-pub --reporter expanded` (expect 321) → `flutter build apk --debug --no-pub`.
4. Phone: `adb devices`, then `adb install -r build\app\outputs\flutter-apk\app-debug.apk`. **Never uninstall or clear data.** Use PowerShell for `adb` paths: Git Bash rewrites `/data/...` paths.
5. Measuring OCR on the device (debug builds only):
   - Run `flutter test tool/probe_images_test.dart` to render synthetic PNGs into `build/ocr_probe/`.
   - Push them to `/data/local/tmp/ocr_probe/`, then run `adb shell "run-as com.inomna.inom_na sh -c 'mkdir -p code_cache/ocr_probe && cp /data/local/tmp/ocr_probe/*.png code_cache/ocr_probe/'"`.
   - Relaunch the app, then run `adb logcat -d -s flutter | findstr IMEDSU_PROBE`.
   - The probe deletes its files afterwards.
6. **Privacy:**
   - Never open, pull or view the user's real prescription photos with Claude tools; that would send medical images off the device.
   - Use synthetic images only, and let the user compare their own photos in Scan details on the phone.
7. Stop at the phase boundary and report: exact test counts, what was actually seen on the device, and what was only tested in code.
