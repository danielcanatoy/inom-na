# Test plan: pagbasa ng reseta (printed + sulat-kamay)

Lahat ng sample ay **gawa ng team**. Sa itaas ng bawat isa, isulat ang **"SAMPLE – FOR DEMO ONLY"** at gumamit ng pekeng pangalan ng pasyente at doktor.
Isulat dito ang **totoong resulta lang**. Kung mali, isulat na mali.

## Setup bago mag-test
- Laptop: tumatakbo ang Ollama, at nakikita ang `qwen2.5:3b` at `qwen2.5vl:3b` sa `ollama list`.
- Phone: Settings → "I-save at subukan" → dapat ✅ ang Text at Vision.
- Ilagay ang papel sa patag na mesa na maliwanag, walang anino. Kunan nang diretso (hindi pahilis) para mapuno ng reseta ang frame.
- Naka-`flutter run` para makita ang mga `[RX]` log.

## Mga sample

| # | Uri | Laman (ito ang "tamang sagot") |
|---|---|---|
| P1 | Printed | Amoxicillin 500mg #21 — 1 cap TID x 7 days, pagkatapos kumain |
| P2 | Printed | Losartan 50mg #30 — 1 tab OD (maintenance) |
| P3 | Printed | 1. Metformin 500mg #60 — 1/2 tab BID before meals · 2. Atorvastatin 20mg #30 — 1 tab HS |
| P4 | Printed (pharmacy label) | Cefalexin 500mg — 1 cap q8h for 1 week, #21 |
| P5 | Printed | 1. Paracetamol 500mg #10 — 1 tab q4h PRN for fever · 2. Cetirizine 10mg #7 — 1 tab OD x 7 days |
| H1 | Sulat-kamay (malinaw) | Amoxicillin 500mg #21 — Sig: 1 cap TID x 7 days |
| H2 | Sulat-kamay (malinaw) | Amlodipine 5mg #30 — Sig: 1 tab OD |
| H3 | Sulat-kamay (malinaw) | Mefenamic Acid 500mg #10 — Sig: 1 cap q8h PRN for pain |
| H4 | Sulat-kamay (karaniwan) | 1. Co-Amoxiclav 625mg #14 — 1 tab BID x 7 days · 2. Omeprazole 20mg #7 — 1 cap OD before breakfast |
| H5 | Sulat-kamay (mahirap/"doctor's handwriting") | Metoprolol 50mg #60 — 1 tab BID |

## Paano i-score (bawat gamot)
Apat na field: **gamot**, **dose**, **frequency** (ilang beses kada araw / PRN), at **araw** (o maintenance).
Bawat field ay ✅ o ❌ base sa nakita sa confirm screen **bago mag-edit**.

## Resulta (punan habang nagte-test)

| # | Parser na ginamit (nakasulat sa confirm screen) | Gamot | Dose | Freq | Araw | Fields na tama | Inayos sa confirm screen? | Tagal (seg) | Notes |
|---|---|---|---|---|---|---|---|---|---|
| P1 | | | | | | /4 | | | |
| P2 | | | | | | /4 | | | |
| P3 | | | | | | /8 | | | |
| P4 | | | | | | /4 | | | |
| P5 | | | | | | /8 | | | |
| H1 | | | | | | /4 | | | |
| H2 | | | | | | /4 | | | |
| H3 | | | | | | /4 | | | |
| H4 | | | | | | /8 | | | |
| H5 | | | | | | /4 | | | |

## Safety regression: maling gamot (Carbocisteine → Cefixime)
Dati, lumabas na "Cefixime" ang sulat-kamay na "Carbocisteine". Pagkatapos ng fix, dapat:
- [ ] HINDI tahimik na lumalabas ang ibang gamot. Kung mali ang pangalan, may ⚠️ at kulay-orange na border.
- [ ] Hindi makaka-save hangga't hindi pinipindot ang "Nasuri ko na" sa bawat ⚠️.
- Isulat dito ang totoong resulta (parser, nabasang pangalan, may ⚠️ ba): ______

## Offline check (dapat gumana pa rin)
- [ ] Naka-off ang WiFi ng phone → i-scan ang P1 → dapat "Offline parser (sa phone)" ang lumabas at may reminder pa rin pagka-save.
- [ ] Naka-off ang Ollama sa laptop → i-type ang reseta → offline parser, walang crash.

Pagkatapos: ilipat ang mga kabuuan sa **Accuracy** table ng README (hiwalay ang printed at sulat-kamay).
