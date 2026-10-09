# CLAUDE.md — IMedsU (AppBuildersPH Hackathon 2026)

> Project instructions for Claude Code. The latest verified code and real-device behavior take precedence over older notes. Work in small, testable increments under the hackathon deadline.

## 1. Communication and language — REQUIRED

- **Always reply to the developer in English**, even if the developer writes in Filipino or Taglish. Use straightforward explanations suitable for a student developer familiar with React/Node/Flask but newer to Flutter.
- Write all progress updates, questions, test reports, commit messages, and implementation summaries in English.
- **All user-facing app UI must be in English:** screen titles, buttons, medication statuses, instructions, error messages, warnings, permissions, settings, and notification text. The official product name is **IMedsU** (exact spelling/capitalization; formerly "Inom Na!").
- The rebrand is public-facing only. Do **not** rename the Dart package `inom_na`, Android application ID, Kotlin package, method channel `com.inomna/reminders`, notification channel ID `inom_na_doses`, or SharedPreferences keys — renaming them would break installs and saved data.
- Keep original prescription contents, medicine names, dose instructions, and user-provided medical text intact. Do not automatically translate or reinterpret source directions in a way that changes their medical meaning.
- Centralize UI strings where practical and use consistent, plain-English terms: **Mark as Taken**, **Upcoming**, **Not Taken**, **Missed**, **I've Verified This**, **Handwritten**, **My Daily Routine**, **Medication**, **Scheduled Time**, **Remind Me Again**.
- Do not show a UI status, progress count, or control unless supported by real functionality. In particular, missed-dose status and full-screen alarm mode are not implemented yet.

## 2. Hackathon context

- **Event:** AppBuildersPH Hackathon 2026 — theme **Local AI**: “Build an AI product that remains genuinely useful when the cloud disappears.”
- **Submission deadline:** October 10, 2026, **9:00 AM Asia/Manila**, no extensions. **Feature freeze: 5:00 AM**.
- **Pitch:** 5-minute live demo + 3-minute judge Q&A. Prioritize a product that demonstrably works over slide polish.
- **Judging:** Problem & Usefulness 25%; Local AI Implementation 25%; Technical Execution 20%; Innovation 15%; Product & Demo Quality 15%.
- Meaningful AI inference must run locally; the core must not depend on cloud AI. Disclose actual models, frameworks, APIs, and AI development tools. **Never fabricate accuracy, latency, benchmarks, or device-test results.**

## 3. Product and final scope

**IMedsU** (formerly Inom Na!) is an offline-first prescription-reading and medication-reminder app for Filipino patients and caregivers, especially people managing multiple medicines.

**Protect this end-to-end workflow:**

1. Photograph a printed prescription or pharmacy label, choose an image, or enter prescription text.
2. Use local OCR and local AI where connected; provide a phone-only fallback when laptop Ollama is unavailable.
3. Display extracted medicine information with source/provenance, uncertainty warnings, and editable fields.
4. Require the user to verify the prescription details before saving.
5. Generate an accurate schedule that honors the prescription, save it, and deliver offline Android reminders.
6. Track which scheduled doses were marked taken; provide meaningful, accurate progress and refill information.

### Three development pillars

1. **Prescription scanning and verification** — printed/handwritten input, OCR, local AI, cautious parsing, review and correction.
2. **Medication scheduling** — validated prescription semantics, exact intervals/explicit times, then user routine-based suggestions when implemented.
3. **Offline reminders and adherence** — reliable notifications, durable records, dose logging, then missed-dose follow-ups when implemented.

**OUT OF SCOPE:** Do not implement “Tanong kay Inom Na”/any IMedsU assistant, a chat screen, chatbot intents, chat actions, free-form chat, Gemini medication explanations, or any cloud AI feature. **Keep Ollama vision/text inference for prescription extraction.**

**Medical safety:** This app organizes doctor/pharmacist instructions. It does **not** diagnose, prescribe, change doses, resolve ambiguous medication directions autonomously, or give medicine-specific missed-dose advice. Unknown/ambiguous data must remain unresolved until the user reviews it and/or consults a pharmacist. Never turn `q8h` into unrelated morning/lunch/evening times. Explicit prescribed times and intervals take precedence over routine preferences.

## 4. Actual architecture

```text
Camera / gallery / typed prescription
    -> ML Kit Text Recognition on Android phone (on-device OCR)
    -> RxParser
         1. Ollama vision model on laptop over local Wi-Fi/LAN (image + OCR)
         2. Ollama text model on laptop over LAN (OCR only)
         3. FallbackParser in Dart on phone (rule-based, no laptop)
    -> medicine-name checks and uncertainty flags
    -> ConfirmScreen (mandatory user verification)
    -> Store (SharedPreferences) + Scheduler (flutter_local_notifications 17.2.4)
    -> Android local reminders + Home dose checklist
```

- **Phone-only fallback is not a phone-hosted LLM.** ML Kit OCR executes locally on the phone; the Dart parser is rule-based; Ollama executes on the laptop.
- Laptop Ollama can run without internet **if the phone and laptop remain connected on the same local network/hotspot**. The phone may send prescription image/OCR text to that laptop; never claim data remains exclusively on the phone in that mode.
- For a full phone-only offline test, turn off the phone's Wi-Fi and cellular data and verify OCR + fallback parsing + saved reminders. For a LAN Ollama test, leave Wi-Fi connected to the laptop but remove internet access; do not claim Ollama works with Wi-Fi disconnected.
- Allow only intended local/private Ollama endpoints and do not send prescription images, text, or patient details to an external cloud service. Do not log sensitive prescription contents.
- Ollama models currently configured: `qwen2.5:3b` (text) and `qwen2.5vl:3b` (vision); verify their installation with `ollama list` and test actual performance.
- If exposing Ollama to the LAN is necessary, confirm host binding (for example, `OLLAMA_HOST=0.0.0.0`) and local firewall/network access; do not expose it to public internet.

### Important files (reconfirm actual paths before editing)

- `lib/main.dart` — initialization and app entry.
- `lib/models/medicine.dart` — medicine model, dose identity, interval/dose generation, tracking, refill calculations.
- `lib/services/ocr.dart` — ML Kit OCR.
- `lib/services/rx_parser.dart` — Ollama vision/text + phone fallback and validation.
- `lib/services/fallback_parser.dart` — offline prescription parsing.
- `lib/services/med_names.dart` — medicine name checks and suggestions.
- `lib/services/store.dart` — local persistence and settings.
- `lib/services/scheduler.dart` — reminder registration/cancellation.
- `lib/services/reminder_planner.dart` — reminder planning (if present; inspect actual repository).
- `lib/screens/home_screen.dart` — today's medication schedule and actions.
- `lib/screens/confirm_screen.dart` — editable, safety-critical confirmation.
- `lib/screens/settings_screen.dart` — AI connection, notification permissions/test, about.
- `lib/ui/` — Phase 2 design system: `app_theme.dart` (colors/theme), `app_strings.dart` (shared English terms), `brand.dart` (IMedsU wordmark + capsule mark), `components.dart` (status badge, banners, empty state, section header, processing dialog), `format.dart` (date/time formatting).
- `lib/services/review_note.dart` — review-note categories (`Conflict:`, `Mismatch:`, `Invalid:`, `Unclear:`). Parsers decide whether a schedule stays unresolved using these prefixes; never match on free-text wording.
- `tool/generate_launcher_icon.dart` — regenerates the launcher icons (`dart run tool/generate_launcher_icon.dart`).
- `android/app/src/main/kotlin/.../MainActivity.kt` — Android native reminder bridge.
- `test/` — parser, validation, scheduler, widget and other tests.
- `PHASE1_REPORT.md`, `README.md`, `TEST_PLAN.md` — implementation handoff, setup, and accuracy/test plans (where present).

## 5. Development environment

- OS: Windows 11; commands are run in **PowerShell**.
- Flutter laptop project path (last reported): `C:\Users\ejcan\Downloads\inom_na\inom_na` — check the actual working directory.
- Flutter **3.47.7**, Dart **3.13.5**; Flutter SDK in `C:\dev\flutter`.
- If `flutter` is not on PATH in a PowerShell session: `$env:Path = "C:\dev\flutter\bin;$env:Path"`.
- Android SDK: `%LOCALAPPDATA%\Android\Sdk`; NDK previously reported: `28.2.13676358`.
- Test device: Poco X7 Pro / Xiaomi-Redmi model `2412DPC0AG`, HyperOS. Check USB debugging, notification permissions, alarms/reminders permission, background autostart, and battery restrictions.
- Ollama runs on a laptop reachable from the phone over the local network.
- Keep `flutter_local_notifications` pinned at **17.2.4** and preserve its v17 scheduling API unless there is an evidenced reason to change it.
- Existing Android setup includes desugaring, manifest notification/reboot permissions and receivers, and a Kotlin reminder bridge. Verify behavior on-device rather than inferring delivery from compilation.

## 6. Current verified status (October 9, 2026)

### Phase 1 — code verified, device verification incomplete

- Codex implementation introduced medication safety validation, exact interval/explicit-time preservation, stable dose IDs, serialized/targeted reminder updates, improved privacy handling, and relevant tests.
- Claude Code verification on the Flutter laptop reported **Flutter dependencies resolved with unchanged lockfile; 129/129 tests passed, zero failed and zero skipped; debug Android APK built; Kotlin native reminder bridge compiled**.
- Analyzer: **0 errors, 0 warnings, 21 pre-existing informational lints**. `flutter analyze` may still exit nonzero because of those infos; don't misreport it as a clean analyzer run.
- Formatting was applied. Phase 1 fixes were not committed or pushed at the time of the handoff; inspect `git status` before further work and create an appropriate checkpoint without losing local changes.
- The original pre-Phase-1 checkpoint was reported as `checkpoint/inomna-phase1-20261009` at `909f6e7`. **This checkpoint does NOT include later uncommitted Phase 1 fixes.**
- A phone screenshot shows Inom Na open on the medication confirmation screen. Therefore the old note that the app could not be installed (`INSTALL_FAILED_USER_RESTRICTED`) is **outdated**; do not treat it as the current blocker. However, scan accuracy, alarm delivery, offline behavior, reboot recovery, and end-to-end native reminder action are **not yet verified** unless new test evidence is supplied.
- **Confirmed UI issue on the phone:** `RIGHT OVERFLOWED BY 22 PIXELS` and `RIGHT OVERFLOWED BY 38 PIXELS` near scheduling type and medication duration dropdowns in `ConfirmScreen`. Fix responsively and add a layout test; preserve validation and schedule logic.

### Phase 2 — English UI/UX redesign and IMedsU rebrand (October 9, 2026, branch `phase2-imedsu-ui`)

- Implemented and code-verified; awaiting the developer's real-device review and approval. See the Phase 2 report in the session for test/build numbers. Do not start Phase 3 without approval.
- Confirm-screen dropdown overflow fixed (`isExpanded`, non-dense, wrapping) with layout tests at 320/393 dp and text scale up to 2.0.

### Phase 3 — My Daily Routine and schedule editing (October 10, 2026, branch `phase3-routine-scheduling`)

- Implemented and code-verified; awaiting real-device review and approval. Do not start Phase 4 without approval.
- Key files: `lib/models/routine.dart` (routine + `RoutineLink`), `lib/services/routine_schedule.dart` (suggestions, proposals), `lib/services/schedule_edit.dart` (effective date, validation, course-count preservation), `lib/screens/routine_screen.dart`, `edit_schedule_screen.dart`, `medication_details_screen.dart`, `lib/ui/routine_suggestion.dart`.
- Schedule history: `Medicine.revisions` (backward-compatible optional JSON field). Earlier rules generate doses before each revision's `until`; never rewrite taken keys or past dose times. Clock-time edits apply from midnight (today only if no dose today has passed/been taken); interval edits apply from the edit time and require a full interval after the last earlier dose. Finite courses keep the same remaining dose count.
- Routine storage key: `daily_routine_v1`. Picker defaults are never treated as a saved routine.

### Phase 4 — follow-ups, dose status, intake history, weekly calendar (October 10, 2026, branch `phase4-reminders-tracking`)

- Implemented and code-verified; on-device alarm registration observed via `adb shell dumpsys alarm` (not delivery). Await approval before Phase 5.
- `Medicine.takenAt` (optional `takenAt` JSON map) stores actual confirmation times for new confirmations; legacy taken keys have none (never invent).
- `lib/services/dose_status.dart`: Upcoming / Taken / Overdue (<2 h) / Missed (>=2 h, tracking label only). Show pharmacist guidance; never give missed-dose advice.
- Follow-ups: `ReminderPlan.build(followUpMinutes:)`, keys `followup:<doseId>` (one-off, finite courses within 7 days) and `followup-daily:<medId>:<HH:mm>` (repeating, ongoing). Primary reminders get capacity first. `cancelDose` removes the dose's follow-up. Settings: `followup_enabled` (default true), `followup_minutes` (10/30/60, default 30).
- `lib/screens/calendar_screen.dart`, `lib/ui/dose_widgets.dart`. Home Scan button is a fixed bottom bar (no FAB over card actions).

### Remaining Phase 1/device risks

- Real HyperOS reminder delivery while locked/backgrounded, after app termination and after reboot.
- Reminder permission denial/revocation and exact-alarm behavior.
- Actual ML Kit OCR, printed/handwritten extraction, Ollama LAN connectivity, and accuracy measurements.
- Existing legacy records may require prescription re-review; avoid overwriting or inventing historic intake timestamps.
- One malformed stored record may currently block registration of reminders for other medicines; report this transparently and prioritize safe recovery if encountered.

## 7. Work order and phase boundaries — follow strictly

### Immediate: phone verification and the confirmed overflow fix

1. Inspect `git status` and preserve the latest implementation in a safe checkpoint (no secrets, no force-push or destructive reset).
2. Fix the two `ConfirmScreen` right-overflow issues with responsive dropdown constraints (`isExpanded`, flexible layout, text handling as appropriate). Verify small widths, longer labels, and enlarged text.
3. Run relevant widget tests, all `flutter test` tests, and the Android debug build. Avoid weakening assertions.
4. On the phone, test typed synthetic prescription -> edit/verify -> save; a near-future real medicine reminder; lock/background behavior; cancellation after marking a dose taken; restart/persistence; and later reboot recovery.
5. Test scanning and local network Ollama separately, and test phone-only fallback with the laptop disconnected. Record actual results.

### Phase 2: English-only UI/UX redesign and IMedsU rebrand (implemented; pending approval)

- Use Flutter Material 3. Design a clean, professional, accessible healthcare UI with calm teal/blue/neutral tones, high contrast, large controls, and responsive layouts.
- Redesign **existing** Home, Scan, Confirm, and Settings experiences, not business logic. Use the IMedsU branding. Support senior users and increased text scaling.
- Translate all **UI and notification messages** into English; preserve unmodified prescription-source text.
- Make uncertainty, missing instructions, editable fields, verified state, and save-blocking errors obvious.
- Show only implemented statuses/counters, backed by actual saved data. Do not fake Missed, Routine, Alarm, refill, or history features.
- Centralize theme/UI strings and reusable medication cards/status elements as useful; avoid unnecessary dependencies and rewrites.
- Test overflow, keyboard, scrolling, contrast, widget behavior, original scan/save workflow, and existing tests/build.
- Stop and report after Phase 2; **do not start new scheduling functionality without approval**.

### Phase 3: My Daily Routine and prescription-safe schedule suggestions

- Add persisted wake-up, breakfast, lunch, dinner, and bedtime settings.
- Generate suggested times for OD/BID/TID/QID/HS and before/after-meal directions **only when supported by verified prescription semantics**.
- Respect explicit prescribed times, fixed `q6h`/`q8h` intervals, dates, and unresolved instructions; do not force meal-based times where medically inappropriate.
- Show editable schedule preview and explicitly confirm future changes. Never silently modify a prescribed interval when the user edits routine preferences.
- Add dedicated time-generation tests and save/restart/reminder-reschedule tests.

### Phase 4: missed-dose tracking and reminder follow-up

- Record actual timestamps on newly marked taken dose events, without inventing timestamps for historic data.
- Display accurate Taken, Upcoming, Overdue/Not Taken, and Missed states and per-medicine counts.
- Add a 30-minute follow-up for an unconfirmed dose, with targeted cancellation once taken.
- Track a dose as missed after the agreed two-hour threshold **for logging only**. Do not tell users to skip, double, or change a dose; send them to the prescription/pharmacist for medicine-specific instructions.
- Verify recurring reminders, idempotent actions, reboot/background behavior, and existing data migration.

### Phase 5: scanner polish and demo hardening (only if time permits)

- Printed vs. Handwritten selection, live scan-seconds counter, name autocomplete and selectable suggestions, bounded timeouts and clear errors.
- Ollama warm-up and `keep_alive` only when measured useful and without harming latency or laptop memory.
- Complete team-made printed/handwritten synthetic-prescription accuracy table; record baseline vs. user-corrected accuracy separately. Never invent results.
- Complete README, disclosure section, demo preparation, and submission before deadline.

### Deferred/out of scope

- No conversational AI assistant/chatbot.
- No cloud medical explanation service.
- No full-screen/lock-screen repeating alarm or snooze mode unless critical core behavior is proven and the user explicitly re-prioritizes it.
- No unrelated app rewrites, dependency upgrades, auth systems, accounts, or cloud backends.

## 8. Hard safety/privacy/engineering constraints

- **Never send medical images or patient information to cloud services.** Local laptop transfer over Wi-Fi must be transparently described and restricted to an intended LAN endpoint.
- Do not log raw prescriptions, medicine names/strengths tied to patient context, or potentially sensitive AI error bodies.
- All inputs/AI JSON/parsed directions require validation before a schedule is saved. Preserve `unknown` versus `once daily`, `maintenance`, or `PRN`.
- Acknowledging a medicine name is not sufficient to verify every other prescription field. A material edit must invalidate prior verification where appropriate.
- Do not schedule from ambiguous directions or silently omit unreadable medicines; user review is mandatory.
- Treat prescribed dose intervals as exact rules, not just frequency counts. Never override explicit times with routine suggestions.
- Avoid `cancelAll` for routine dose updates; preserve stable IDs, targeted cancellation, serialized updates, and reporting of scheduling failures.
- Existing record compatibility matters. Do not delete stored medication data, clear app data, or reset the phone without approval.
- Real Android behavior takes precedence over mocks. Fake-backend notification tests cannot establish that a phone was notified.
- Use **synthetic prescriptions labeled “SAMPLE — FOR DEMO ONLY”** and fictional names for tests/demos. Do not recommend taking actual medicine as part of testing.
- Prefer the smallest reliable change. Run relevant tests and `flutter test`, `flutter analyze`, and a debug Android build when practical. Report command results accurately, including informational lints and skipped checks.
- Ask before pushing/merging branches, releasing builds, or changing device settings. Never commit secrets.

## 9. Demo plan — differentiate two offline modes

**LAN local-AI demo (phone + laptop, no cloud internet):**
1. Phone Wi-Fi stays connected to laptop/local hotspot, but internet uplink is unavailable.
2. Scan a synthetic printed prescription/label with ML Kit and, if working, laptop Ollama.
3. Display the source accurately as **Local AI (Laptop Ollama)**, then review and confirm the extracted information.
4. Save the schedule, demonstrate a verified near-future notification, and show actual dose checklist/progress.

**Phone-only fallback demo (no LAN or internet):**
1. Disconnect Wi-Fi/cellular network.
2. Use on-device OCR and the Dart fallback parser with a supported synthetic prescription.
3. Verify/edit, save, and demonstrate offline reminders/checklist without Ollama.
4. Label processing honestly as **Offline OCR + Rule-Based Parsing**, not laptop local AI.

Use only measured scan latency, OCR accuracy, dose reliability, and observed notification evidence in the final pitch.

## 10. Required disclosures in README

Document verified versions and actual usage of:
- Models: `qwen2.5:3b`, `qwen2.5vl:3b`; on-device ML Kit Text Recognition; local rule-based fallback.
- Flutter/Dart, `flutter_local_notifications`, `shared_preferences`, other material dependencies, and Android native integration.
- Local-network connections and whether prescription data is sent to the laptop; no cloud AI in the core flow.
- **AI development tools: Codex (OpenAI), Claude Code/Claude (Anthropic)**, plus any other tools actually used.
- Source provenance/reused assets/code, if any; make no unsupported claims that all code was developed from scratch.
- Synthetic test data, actual accuracy/results, known constraints and devices tested.

## 11. Claude Code response contract

At the beginning of a task, briefly state the specific files/features you'll examine and your plan. During implementation, provide concise updates in **English**. At completion, report: files changed, behavior changed, safety implications, actual tests/builds run and results, Android observations vs. untested assumptions, known remaining risks, and what should happen next. **Stop at the agreed phase boundary and wait for approval.**
