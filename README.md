# Inom Na! 💊

**Kunan ng picture ang reseta. Kami na ang magpapaalala, kahit walang internet.**

AppBuildersPH Hackathon 2026 · Local AI

## Problem
Pag-uwi galing sa doktor, nakakalimutan, nadodoble, o hindi natatapos ng pasyente ang gamot. Pinakaapektado ang seniors na maraming maintenance na gamot, at ang mga tumitigil sa antibiotic kapag gumaan na ang pakiramdam.

**Target user:** pasyente at caregiver, lalo na ang seniors at ang pamilyang nag-aalaga sa kanila.

## Paano gumagana
1. Kukunan ng picture ang reseta o label ng gamot.
2. **On-device OCR** (Google ML Kit) ang magbabasa ng text.
3. **Local AI via Ollama** sa laptop (parehong WiFi/hotspot, walang internet):
   - **Vision model** (`qwen2.5vl:3b`) ang tumitingin mismo sa larawan. Pinakamaganda ito para sa sulat-kamay.
   - Kapag hindi gumana, **text model** (`qwen2.5:3b`) ang iintindi sa OCR text (TID, BID, q8h, PRN, "x 7 days", "#21").
   - Kapag hindi maabot ang Ollama, **offline parser sa phone** ang gagamitin.
   - **Auto-correct ng pangalan ng gamot** (listahan ng karaniwang gamot sa PH, sa phone).
   - Ipinapakita sa confirm screen kung alin sa tatlo ang bumasa.
4. **Confirm screen:** iche-check at aayusin ng user bago gumawa ng reminder.
5. **Offline reminders** sa bawat dose, may "Nainom na" checklist.
6. **Refill alert** 3 araw bago maubos ang nabili.
7. **Adherence log** ("Nainom 19/21") na pwedeng ipakita sa doktor.

## Why local?
- **Medical data ang reseta.** Hindi ito dapat umalis sa device o mapunta sa cloud.
- **Dapat gumana ang reminders kahit walang internet o load.** Ang paalala na nakadepende sa cloud ay hindi maaasahan.

## What runs locally
| Bahagi | Saan tumatakbo |
|---|---|
| OCR ng reseta | Phone (Google ML Kit, on-device) |
| Pagbasa ng larawan (sulat-kamay) | Laptop sa parehong WiFi/hotspot (Ollama, `qwen2.5vl:3b`), walang internet |
| Pag-intindi ng reseta | Laptop sa parehong WiFi/hotspot (Ollama, `qwen2.5:3b`), walang internet |
| Auto-correct ng pangalan ng gamot | Phone (Dart) |
| Backup parser | Phone (Dart rules) |
| Reminders, checklist, refill alert, log | Phone (local notifications, local storage) |

## What requires internet
- Wala sa core features. *(Kung idadagdag ang Gemini para sa paliwanag ng gamot: pangalan lang ng gamot ang ipapadala, walang pangalan ng pasyente o larawan.)*

## Setup

### 1. Laptop (Ollama)
```bash
ollama pull qwen2.5:3b
ollama pull qwen2.5vl:3b
# Para maabot ng phone sa parehong WiFi/hotspot:
OLLAMA_HOST=0.0.0.0 ollama serve          # macOS/Linux
```
**Windows:** `[Environment]::SetEnvironmentVariable('OLLAMA_HOST','0.0.0.0','User')`, i-restart ang Ollama, at payagan ang port 11434 sa firewall (Admin PowerShell):
`New-NetFirewallRule -DisplayName "Ollama 11434" -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow -Profile Any`
Hanapin ang IP ng laptop (`ipconfig` / `ifconfig`), tapos ilagay sa app: Settings ⚙️ → `http://<IP>:11434`. Pindutin ang "I-save at subukan".

### 2. Flutter app
```bash
flutter create inom_na_app --org com.inomna
# kopyahin ang lib/, test/, at pubspec.yaml dito sa bagong project
flutter pub get
flutter run        # sa TUNAY na Android phone, hindi emulator
flutter test       # parser tests
```

### 3. Android config (kailangan!)
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
*(Kung `build.gradle` (Groovy) ang project: `coreLibraryDesugaringEnabled true` at `coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`.)*

**`android/app/src/main/AndroidManifest.xml`**: sa loob ng `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```
Sa `<application ...>` idagdag ang `android:usesCleartextTraffic="true"` (para sa `http://` papunta sa laptop), at sa loob nito:
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

## Test data
Lahat ng resetang ginamit sa testing at demo ay **gawa ng team**, may pekeng pangalan ng pasyente at doktor ("SAMPLE – FOR DEMO ONLY"). Walang totoong medical record na ginamit.

## Accuracy *(punan pagkatapos mag-test)*
Paraan: tingnan ang [TEST_PLAN.md](TEST_PLAN.md). Totoong resulta lang ang isinusulat dito.

| | Printed | Sulat-kamay |
|---|---|---|
| Bilang ng sample na reseta | __ | __ |
| Parser na ginamit (vision / text / offline) | __ | __ |
| Fields na tama (gamot, dose, frequency, araw) | __% | __% |
| Resetang buong tama | __ / __ | __ / __ |
| Naitama sa confirm screen | __ | __ |
| Karaniwang tagal ng pagbasa | __ seg | __ seg |

## Disclosures
- **Models:** `qwen2.5:3b` (text) at `qwen2.5vl:3b` (vision) via Ollama; Google ML Kit Text Recognition (on-device)
- **Frameworks/libraries:** Flutter, google_mlkit_text_recognition, image_picker, http, flutter_local_notifications, timezone, shared_preferences
- **APIs/cloud services:** wala sa core
- **Existing code/assets:** wala; ginawa during the hackathon
- **AI development tools:** Claude (Anthropic), kasama ang Claude Code, para sa code scaffolding, debugging at planning

## Hindi ito medical advice
Tumutulong lang ang app na sundin ang bilin ng doktor. Laging may confirm screen bago gumawa ng reminder.

## Team
- __
