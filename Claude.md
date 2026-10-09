# CLAUDE.md — Inom Na! (Hackathon project)

## Language

Reply to the user in simple **Taglish/Tagalog**. Keep app UI strings in Tagalog.
The user is a student developer (strong in React/Node/Flask, **new to Flutter**). Explain errors briefly and plainly, then fix them.

## The hackathon (context for every decision)

- **AppBuildersPH Hackathon 2026, theme: Local AI.** "Build an AI product that remains genuinely useful when the cloud disappears."
- **Submission deadline: 9:00 AM, Oct 10, 2026 (Asia/Manila). No extensions.** Feature freeze at 5:00 AM.
- Pitch: 5 min live demo + 3 min judge Q&A. Working product > slides.
- **Judging:** Problem & Usefulness 25% · Local AI Implementation 25% · Technical Execution (works reliably live) 20% · Innovation 15% · Product & Demo Quality 15%.
- **Rules:** substantially built during the hackathon; a meaningful part of AI inference must run locally; core local AI must work without depending on a cloud AI API (cloud only as a secondary component); disclose every model, framework, API, and AI dev tool. **Fake benchmarks = disqualification.** Report only real test results.

## The product

**Inom Na!** — patient takes a photo of a prescription or pharmacy label → app reads it → user confirms → app schedules **offline** medicine reminders, tracks doses taken, alerts before medicine runs out.
Target user: Filipino patients and caregivers, especially seniors on multiple maintenance meds.
Why local: prescriptions are medical data (must not leave the device), and reminders must work without internet.

## Architecture

```
Photo ─▶ ML Kit OCR (on-device)
      ─▶ RxParser.parseImage
            1. Ollama vision model on laptop (image + OCR text)   ── best for handwriting
            2. Ollama text model on laptop (OCR text only)
            3. FallbackParser (Dart regex, on phone)               ── always works offline
      ─▶ MedNames.correct (fuzzy-fix drug names)
      ─▶ ConfirmScreen (user edits/approves — REQUIRED safety step)
      ─▶ Store (shared_preferences) + Scheduler (flutter_local_notifications)
```

Phone reaches Ollama over the same WiFi/hotspot (no internet needed). Ollama must run with `OLLAMA_HOST=0.0.0.0`.

### Files

- `lib/main.dart` — app entry, init Store + Scheduler
- `lib/models/medicine.dart` — Medicine model, dose generation (`allDoses`), refill math, default times
- `lib/services/ocr.dart` — ML Kit text recognition
- `lib/services/rx_parser.dart` — Ollama calls (text + vision), fallback chain, `ping()`
- `lib/services/fallback_parser.dart` — offline regex parser (TID/BID/q8h/PRN/HS, "x 7 days", "#21", 1/2 tab, AC/PC)
- `lib/services/med_names.dart` — common PH drug list + Levenshtein auto-correct
- `lib/services/scheduler.dart` — notifications, reschedule all, refill alert, 1-minute test
- `lib/services/store.dart` — local persistence + Ollama settings
- `lib/screens/home_screen.dart` — today's doses checklist, meds list, adherence, refill banner, scan/type flow
- `lib/screens/confirm_screen.dart` — editable parsed result
- `lib/screens/settings_screen.dart` — Ollama URL, text model, vision model, connection test
- `test/fallback_parser_test.dart` — parser + auto-correct tests
- `README.md` — setup, Android config, submission sections (accuracy table still to fill)

## Environment

- Windows 11, **PowerShell**. Project: `C:\Users\ejcan\Downloads\inom_na\inom_na`
- Flutter 3.47.7 (stable) at `C:\dev\flutter`. Developer Mode ON.
- Android SDK at `%LOCALAPPDATA%\Android\Sdk`; NDK 28.2.13676358 installed via Android Studio.
- Test phone: **Xiaomi/Redmi `2412DPC0AG`** (HyperOS). Needs "Install via USB" + "USB debugging (Security settings)"; set app Autostart ON and battery "No restrictions" or reminders may not fire.
- Ollama on the same laptop. Models: `qwen2.5:3b` (text), `qwen2.5vl:3b` (vision). Check with `ollama list`.
- Android config already done: core library desugaring in `android/app/build.gradle.kts`; permissions, `usesCleartextTraffic`, and flutter_local_notifications receivers in `AndroidManifest.xml`.

## Current status

- `flutter test` passes. Debug APK builds.
- Last blocker: `INSTALL_FAILED_USER_RESTRICTED` (Xiaomi blocked USB install). User is fixing phone settings.
- Code was written without being compiled on a device first — expect a few compile/runtime issues; fix them minimally.

## Priorities (in order — don't skip ahead)

1. App installs and opens on the Redmi. Typed prescription → confirm → save works.
2. Notifications fire (use the 🔔 1-minute test button). Fix permissions / exact alarms / Xiaomi battery issues.
3. Ollama connection from phone works (Settings → "I-save at subukan"). Text parse shows "Local AI (Ollama)".
4. Camera scan works on printed prescriptions; then vision model on clear handwriting.
5. Accuracy test: run 10–15 team-made sample prescriptions, record REAL results, fill the README accuracy table.
6. Polish only if time remains: UI clarity, empty/error states, loading text.
7. Optional, only after 1–5 are solid: caregiver adherence summary or Gemini drug explanation (send **drug name only**, never images or patient info; must be clearly secondary and disabled offline).

## Hard constraints

- **Never send prescription images or patient data to any cloud service.**
- Keep the offline fallback chain working. The app must still create reminders with WiFi OFF and Ollama unreachable.
- Keep the Confirm screen; never auto-create reminders without user approval.
- Not medical advice: the app helps follow the doctor's instructions; it does not diagnose or change doses.
- Don't rewrite the architecture or swap libraries unless something is truly broken. Prefer the smallest fix.
- `flutter_local_notifications` is pinned to v17 — the code uses the v17 `zonedSchedule` API. Don't bump the major version.
- Don't commit secrets. If a Gemini key is ever added, keep it in a git-ignored file.
- Test data: only team-made fake prescriptions ("SAMPLE – FOR DEMO ONLY", fake patient/doctor names).
- After every change: run `flutter test` (and `flutter analyze` if quick) before saying it's done.

## Demo flow to protect

1. Turn WiFi/data OFF on the phone (laptop hotspot only, no internet).
2. Scan a printed sample prescription → result shows "Local AI".
3. Confirm screen → save → schedule shown.
4. 🔔 test reminder fires within 1 minute.
5. Show checklist ("Nainom na"), adherence count, refill alert.
6. Show real accuracy numbers.

## Disclosures to keep in README

Models (qwen2.5:3b, qwen2.5vl:3b, ML Kit Text Recognition), frameworks/libraries, APIs (none in core), existing code (none), AI dev tools: **Claude (Anthropic), including Claude Code**.
