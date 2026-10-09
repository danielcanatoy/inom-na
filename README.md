# IMedsU

**Your Medication. Your Schedule. Your Health.**

Photograph a prescription, review what was read, and get medication reminders that work without internet.

AppBuildersPH Hackathon 2026 · Local AI

> IMedsU was previously named "Inom Na!". The Dart package (`inom_na`), Android application ID, storage keys and notification channel IDs keep their original identifiers so existing installs and saved data keep working.

## Problem
After a doctor's visit, patients forget doses, take them twice, or stop antibiotics early once they feel better. Seniors managing several maintenance medicines are affected most.

**Target users:** Filipino patients and caregivers, especially seniors and the family members who help them.

## How it works
1. Take a photo of a prescription or pharmacy label, choose one from the gallery, or type the prescription. A scan shows its progress (stage and elapsed time) and can be cancelled; a cancelled scan saves nothing.
2. **Phone Only (default, no laptop or internet):** Google ML Kit OCR reads the text on the phone. The text is put in reading order (rows top to bottom, left to right), then a **rule-based Dart reader** (not an AI model) extracts candidate fields: strength, amount, times per day / q6h / q8h, PRN, "x 7 days", quantity, "ongoing". Unclear characters (e.g. "5OOmg", "I tab") are read and **flagged**, never silently accepted.
3. **Enhanced AI (optional, Settings → Prescription Reading):** the photo and OCR text are sent over the local Wi-Fi/hotspot to **Ollama on a laptop** — vision model `qwen2.5vl:3b` first, then text model `qwen2.5:3b`. If the laptop cannot be reached, IMedsU says so and uses the phone reader.
   - **Medication-name suggestions** from a short list of common PH medicines are offered as "Use '…'" chips; names are never auto-replaced.
   - **Strength check** flags unusually large strengths or a strength that differs from the prescription text; strengths are never changed.
   - The review screen shows which reader was used.
4. **Review Prescription screen:** compact cards per medicine, **Edit Details** and **Verify Medication** (explicit confirmation). Unclear, missing or invalid details block verification and saving. **Scan details** shows the photo, the raw and processed OCR text, and what is still missing, and can re-read corrected text. If nothing is identified, the recognized text can be corrected and read again, or the medicine entered manually.
5. **Offline reminders** for each dose, with a "Mark as Taken" checklist and today's progress.
   - **My Daily Routine** (wake-up, meals, bedtime) suggests reminder times for general daily frequencies. Suggestions are applied only when the user taps "Use These Times"; prescribed clock times and fixed intervals (q6h/q8h) are never replaced, and before/after-meal offsets are never assumed.
   - **Follow-up reminders** (on by default, 10/30/60 minutes, Settings → Notifications): one extra notification for the SAME dose if it is not marked taken; cancelled when marked taken. Never an extra dose. Repeating follow-ups for ongoing medicines; finite courses get follow-ups for the next 7 days, refreshed whenever the app opens.
   - **Dose status:** Upcoming, Taken, Overdue (unconfirmed, under 2 hours), Missed (no confirmation recorded after 2 hours — a tracking label, not proof). New confirmations store the actual time; older records show "time not recorded".
   - **Medication Calendar** (bottom navigation: Home / Calendar / Medications): weekly strip, Jump to Date, Go to Today, and a chronological timeline per day; late confirmations allowed for past doses. Viewing dates never changes a medicine.
   - **Edit Schedule** changes future reminders only. Today's remaining doses can change from now only if today keeps exactly the prescribed number of doses; otherwise the change starts tomorrow. Past doses, taken records and the number of doses in a finite course are kept. Routine changes propose updates for routine-linked medicines and apply only after confirmation.
   - **Edit Medication** corrects name, strength, amount, schedule type, times, duration, directions and quantity, with renewed verification. The original prescription text is kept unchanged as evidence.
   - **Reminder isolation:** if one saved medicine's schedule cannot be planned, it is reported by name and its existing reminders are kept; all other medicines are still scheduled.
6. **Running-low alert** about 3 days before the purchased quantity runs out.
7. **Dose record** (for example "Marked taken: 19 of 21 planned doses") that can be shown to a doctor.

## Why local?
- **Prescriptions are medical data.** The photo and the OCR text are sent only to the configured Ollama laptop on the local network. Use local models and a trusted Wi-Fi/hotspot; the HTTP connection is not encrypted. Medications and the checklist are stored on the phone.
- **Reminders must work without internet or mobile load.** Cloud-dependent reminders are not reliable.

## What runs where
| Part | Where it runs |
|---|---|
| Prescription OCR | Phone (Google ML Kit, on-device, bundled model) |
| Phone Only reading (default) | Phone (rule-based Dart reader; not an AI model) |
| Enhanced AI: reading the photo | Laptop on the same Wi-Fi/hotspot (Ollama, `qwen2.5vl:3b`), optional, no internet |
| Enhanced AI: interpreting the text | Laptop on the same Wi-Fi/hotspot (Ollama, `qwen2.5:3b`), optional, no internet |
| Name suggestions, strength checks | Phone (Dart) |
| Reminders, follow-ups, checklist, calendar, running-low alert, dose record | Phone (local notifications, local storage) |

**Limitations:** Phone Only reads clearly printed text well (see Accuracy) but **does not reliably read handwriting**; use Enhanced AI or correct the text / enter the medicine manually. Automatic cropping or image enhancement is **not implemented**.

## What requires internet
Only the first download of Flutter dependencies, OCR resources if needed, and the local Ollama models. There is no cloud service in the core workflow. After setup there are two modes: phone-only (OCR + offline reader + checklist + reminders) and laptop-connected local AI.

## Setup

### 1. Laptop (Ollama)
```bash
ollama pull qwen2.5:3b
ollama pull qwen2.5vl:3b
# So the phone can reach it on the same Wi-Fi/hotspot:
OLLAMA_HOST=0.0.0.0 ollama serve          # macOS/Linux
```
**Windows:** `[Environment]::SetEnvironmentVariable('OLLAMA_HOST','0.0.0.0','User')`, restart Ollama, and allow port 11434 in the firewall (Admin PowerShell):
`New-NetFirewallRule -DisplayName "Ollama 11434" -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow -Profile Any`
Find the laptop's IP address (`ipconfig` / `ifconfig`), then in the app open **Settings → AI Connection**, enter `http://<IP>:11434` and tap **Save and Test Connection**.

### 2. Flutter app
```bash
# Keep android/ in the checkout; it contains the native reminder bridge.
flutter pub get --enforce-lockfile
flutter run        # on a REAL Android phone, not an emulator
flutter analyze
flutter test       # model, parser, persistence, review, reminder and UI tests
```

### 3. Launcher icon
The launcher icon (teal background, two-tone capsule) is generated without extra dependencies:
```bash
dart run tool/generate_launcher_icon.dart
```

### 4. Android configuration (required)
**`android/app/build.gradle.kts`**
```kotlin
android {
    defaultConfig { minSdk = 21 }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```
*(For a Groovy `build.gradle` project: `coreLibraryDesugaringEnabled true` and `coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`.)*

**`android/app/src/main/AndroidManifest.xml`**, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```
In `<application ...>` add `android:usesCleartextTraffic="true"` (for `http://` to the laptop), and inside it:
```xml
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

**Xiaomi / Redmi / POCO (HyperOS/MIUI):** in App info for IMedsU, turn **Autostart** on and set **Battery saver** to **No restrictions**, otherwise reminders may not appear while the app is closed.

## Test data
All prescriptions used in testing and demos are **made by the team**, with fake patient and doctor names ("SAMPLE – FOR DEMO ONLY"). No real medical records were used.

## Accuracy (measured results only)
Method: team-made **synthetic** prescriptions ("SAMPLE / NOT FOR MEDICAL USE") rendered as images on the laptop and read by **real ML Kit on the Poco X7 Pro** (debug-only probe, `lib/services/ocr_probe.dart`), then by the Phone Only reader. These are clean rendered images, **not camera photos**.

| | Printed (synthetic rendered images, Phone Only) | Handwritten |
|---|---|---|
| Number of sample images | 7 (clean, small print, low resolution, table layout, abbreviated, PRN syrup, clinic header with 2 medicines) | Not measured |
| Medicines identified | 8 / 8 | Not measured |
| Medicines with every field correct | 6 / 8 (the other 2: OCR read "Amoxicilin" — a suggestion is offered; "15 mg/5 m" — the dropped "L" is left for the user to complete) | Not measured |
| False medicines | 0 | Not measured |
| OCR time on the phone | about 70–180 ms per image (about 1 s for the first scan) | Not measured |

Not yet measured: real camera photos, handwriting, and Enhanced AI (laptop Ollama) accuracy. See also `test/scanner_benchmark_test.dart` (rule-based reader on synthetic text: 72/72 fields).

## Disclosures
- **Models:** `qwen2.5:3b` (text) and `qwen2.5vl:3b` (vision) via Ollama on a laptop; Google ML Kit Text Recognition (on-device); a local rule-based fallback parser.
- **Frameworks/libraries:** Flutter (Material 3), google_mlkit_text_recognition, image_picker, http, flutter_local_notifications 17.2.4, timezone, shared_preferences; a small Kotlin bridge for daily reminder scheduling.
- **APIs/cloud services:** none in the core workflow.
- **Existing code/assets:** none reused; built during the hackathon. The logo and launcher icon are drawn in code (`lib/ui/brand.dart`, `tool/generate_launcher_icon.dart`).
- **AI development tools:** Codex (OpenAI) and Claude (Anthropic), including Claude Code, for code scaffolding, debugging, testing and planning.

## Not medical advice
IMedsU helps people follow their doctor's or pharmacist's instructions. It does not diagnose, prescribe or change doses. A review screen is always shown before any reminder is created.

## Current scope
Prescription scanning and verification, accurate medication scheduling, and offline reminders/checklist only. There is no chatbot. Ollama vision/text is kept for prescription extraction. See [PHASE1_REPORT.md](PHASE1_REPORT.md) for the Phase 1 baseline and safety changes.

## Team
- __
