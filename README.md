# IMedsU

**Your Medication. Your Schedule. Your Health.**

Photograph a prescription, review what was read, and get medication reminders that work without internet.

AppBuildersPH Hackathon 2026 · Local AI

> IMedsU was previously named "Inom Na!". The Dart package (`inom_na`), Android application ID, storage keys and notification channel IDs keep their original identifiers so existing installs and saved data keep working.

## Problem
After a doctor's visit, patients forget doses, take them twice, or stop antibiotics early once they feel better. Seniors managing several maintenance medicines are affected most.

**Target users:** Filipino patients and caregivers, especially seniors and the family members who help them.

## How it works
1. Take a photo of a prescription or pharmacy label, choose one from the gallery, or type the prescription.
2. **On-device OCR** (Google ML Kit) reads the text on the phone.
3. **Local AI via Ollama** on a laptop on the same Wi-Fi/hotspot (no internet needed):
   - **Vision model** (`qwen2.5vl:3b`) reads the photo itself — best for handwriting.
   - Otherwise the **text model** (`qwen2.5:3b`) interprets the OCR text (TID, BID, q8h, PRN, "x 7 days", "#21").
   - If Ollama cannot be reached, the **offline rule-based reader on the phone** is used.
   - **Medication-name check** against a list of common PH medicines (on the phone).
   - The review screen shows which of these read the prescription.
4. **Review Prescription screen:** the user checks, corrects and verifies every medication. Unclear, missing or invalid details block saving.
5. **Offline reminders** for each dose, with a "Mark as Taken" checklist and today's progress.
6. **Running-low alert** about 3 days before the purchased quantity runs out.
7. **Dose record** (for example "Marked taken: 19 of 21 planned doses") that can be shown to a doctor.

## Why local?
- **Prescriptions are medical data.** The photo and the OCR text are sent only to the configured Ollama laptop on the local network. Use local models and a trusted Wi-Fi/hotspot; the HTTP connection is not encrypted. Medications and the checklist are stored on the phone.
- **Reminders must work without internet or mobile load.** Cloud-dependent reminders are not reliable.

## What runs where
| Part | Where it runs |
|---|---|
| Prescription OCR | Phone (Google ML Kit, on-device) |
| Reading the photo (handwriting) | Laptop on the same Wi-Fi/hotspot (Ollama, `qwen2.5vl:3b`), no internet |
| Interpreting the prescription text | Laptop on the same Wi-Fi/hotspot (Ollama, `qwen2.5:3b`), no internet |
| Medication-name check | Phone (Dart) |
| Backup reader | Phone (rule-based Dart parser) |
| Reminders, checklist, running-low alert, dose record | Phone (local notifications, local storage) |

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

## Accuracy *(fill in after testing)*
Method: see [TEST_PLAN.md](TEST_PLAN.md). Only real results are recorded here.

| | Printed | Handwritten |
|---|---|---|
| Number of sample prescriptions | __ | __ |
| Reader used (vision / text / offline) | __ | __ |
| Correct fields (medicine, dose, frequency, days) | __% | __% |
| Fully correct prescriptions | __ / __ | __ / __ |
| Corrected on the review screen | __ | __ |
| Typical reading time | __ s | __ s |

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
