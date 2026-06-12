# Livescript

Livescript is a macOS floating live transcription app for meetings and videos.

It captures microphone audio and system audio (Zoom, Google Meet, browser, YouTube, etc.), transcribes in real time on-device, and lets you export transcripts locally.

## Current Features

- Floating always-on-top transcript window with auto-scroll (follows latest text unless you scroll up)
- Best-effort window capture exclusion (`NSWindow.sharingType = .none`)
- Audio source modes: `Mic`, `System`, `Mixed`
- On-device transcription with **English / Chinese** detection (Smart profile routes refine by language)
- **Smart** profile (default): Zoom-style **draft → refine** captions
  - Fast **draft**: SenseVoice decodes ~1s incremental audio hops and **accumulates** text into a growing sentence
  - **Refine on pause** (~400ms silence): full utterance re-decode replaces the draft in place
  - English refine: **distil-large-v3** (WhisperKit)
  - Chinese refine: **SenseVoice** (distil-large-v3 is English-only)
- **Balanced / Quality** profiles: single-pass Whisper on fixed 2s chunks
- Models stored under `~/workspace/models/` (not bundled in the app)
- Local-first model loading, with WhisperKit fallback download when missing
- Real-time model preparation / download status in UI
- Speaker labeling for mixed input (`You` / `System`)
- Device-aware echo-bleed filtering (built-in vs headset mic)
- Selectable transcript text with colorized speaker labels
- Export `.txt` / `.md` (refined segments only)
- Session checkpointing for long-running meetings

## Tech Stack

- SwiftUI + AppKit (`NSPanel`, `NSTextView`)
- AVFoundation (microphone capture)
- ScreenCaptureKit (system audio capture)
- **WhisperKit** — Balanced/Quality ASR; English refine (distil-large-v3) in Smart profile
- **sherpa-onnx** — SenseVoice-Small draft + optional VAD / punctuation
- SpeakerKit (speaker diarization groundwork, not surfaced in UI)

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode 15+

## Unit Tests

32 regression tests for the Smart captions pipeline, language routing, chunk ordering, and hallucination filtering:

```bash
./scripts/run_unit_tests.sh
```

Uses Swift Package Manager (`Package.swift`, `Livescript/Domain/`).

## Models

All user models live in **`~/workspace/models/`** (override with `LIVESCRIPT_MODELS_DIR`):

```
~/workspace/models/
├── sensevoice/                 # SenseVoice-Small (Smart draft + Chinese refine)
│   ├── model.int8.onnx
│   └── tokens.txt
├── punctuation/                # Optional ct-punc (English refine polish)
│   ├── model.onnx
│   └── tokens.json
├── vad/                        # Optional Silero VAD
│   └── silero_vad.onnx
└── models/                     # WhisperKit (English refine + Balanced/Quality)
    └── argmaxinc/whisperkit-coreml/
        ├── distil-whisper_distil-large-v3/
        ├── openai_whisper-small/
        └── openai_whisper-large-v3-v20240930_626MB/
```

Sherpa runtime libs are fetched to `ThirdParty/sherpa-onnx/` by the download script (not committed).

Download everything:

```bash
./scripts/download_all_models.sh
```

Notes:

- SenseVoice, VAD, and punctuation download from **GitHub releases** (sherpa-onnx).
- distil-large-v3 pre-download needs `huggingface-cli` (`pip install huggingface_hub`), or WhisperKit downloads it on first Smart session.
- Scripts are executable (`chmod +x scripts/*.sh` if needed).

## Local Production Build

### Option A: One-command build (recommended)

```bash
./scripts/build_release_local.sh
```

Runs `download_all_models.sh`, then Release build. Output: **`dist/Livescript.app`**

### Option B: Build + install + launch

```bash
./scripts/install_release_local.sh
```

Runs tests, downloads models, builds, copies to `/Applications/Livescript.app`, and opens the app.

### Option C: Optional DMG

```bash
./scripts/package_dmg_local.sh
```

Output: `dist/Livescript-local.dmg`

### Option D: Build from Xcode

1. Open `Livescript.xcodeproj`.
2. Scheme `Livescript`, **Product > Build For > Running**, `Release`.
3. Copy the app from DerivedData, or use the scripts above.

## Install on Your Mac

1. Build with `./scripts/build_release_local.sh` (or use `install_release_local.sh`).
2. Drag `dist/Livescript.app` to `/Applications`, or use the install script.
3. Launch Livescript.

App is not notarized in this workflow; Gatekeeper may prompt on first open.

## First-run Permissions

- **Microphone** — required for `Mic` / `Mixed`
- **Screen & System Audio Recording** — required for `System` / `Mixed`
- **Files and Folders** — when choosing session / model directories

If system audio stays denied: quit the app, re-toggle **Screen & System Audio Recording** for Livescript in System Settings, relaunch.

If model setup fails: run `./scripts/download_all_models.sh`, confirm `~/workspace/models/sensevoice/` exists, or pick a custom folder in the app **Model** menu.

## Usage

1. (Once) `./scripts/download_all_models.sh`
2. Click **Start** and choose a session folder.
3. Pick **Source** (`Mic` / `System` / `Mixed`) and **Speed** (`Smart` is default).
4. Read live captions in the floating window.
5. **Export > TXT** or **Export > Markdown** when done.

## Speed Profiles

| Profile | Engine | Draft | Refine (on pause) | Typical lag |
|---------|--------|-------|-------------------|-------------|
| **Smart** (default) | SenseVoice + Whisper | ~1s hops, incremental text build | EN: distil-large-v3 · ZH: SenseVoice | draft ~0.5–1.5s · refine ~2–3.5s |
| **Balanced** | Whisper `small` | — | — (single pass, 2s chunks) | ~2–3s |
| **Quality** | Whisper `large-v3` | — | — (single pass, 2s chunks) | ~4–6s |

Legacy UserDefaults value `realtime` maps to **Smart**.

### Smart captions flow

1. While someone speaks, draft text updates about every **1 second** (each hop decodes ~1s of new audio; text is **merged** into one growing line).
2. On **~400ms pause**, the full utterance (up to **8s**) is refined and **replaces** the draft in place.
3. Draft and refined lines use the **same** text styling (no gray “partial” mode).
4. Optional **punctuation** runs after English refine only.
5. **Mixed mode**: echo bleed from speakers is filtered; use **headphones** for best `You` vs `System` separation.
6. Annotations like `(keyboard clicking)` and short hallucination fragments are filtered.

Long-session stability: draft hops stay fast (fixed ~1s decode size); refine jobs coalesce when backed up; VAD is optional and not on the hot audio path.

## Project Structure

```
Livescript/
├── ContentView.swift              # Floating UI
├── ViewModels/TranscriptionViewModel.swift
├── Domain/
│   ├── UtteranceBuffer.swift      # Draft hops + pause detection
│   ├── TranscriptionSpeedProfile.swift
│   └── LanguageDetector.swift     # EN/ZH routing for refine
├── Services/
│   ├── TranscriptionService.swift # Draft/refine orchestration
│   ├── SenseVoiceTranscriber.swift
│   ├── WhisperTranscriber.swift
│   ├── AudioCaptureCoordinator.swift
│   └── TranscriptExporter.swift
├── UI/SelectableTranscriptTextView.swift
LocalPackages/SherpaOnnx/          # sherpa-onnx Swift wrapper
scripts/                           # Build, model download, tests
Tests/LivescriptCoreTests/         # SPM unit tests
TECH_DESIGN.md                     # Architecture notes (may lag code)
```

## Known Limitations

- Screen capture exclusion is best-effort.
- Speaker labels are source-based (`You` / `System`), not person-level diarization.
- Smart refine targets **English and Chinese** only; other languages are not supported.
- Export includes **refined** segments only (not in-progress drafts).
- distil-large-v3 is English-only; Chinese utterances stay on SenseVoice for refine.

## Roadmap Ideas

- Person-level diarization in UI
- Export formats (`json`, `srt`)
- Hotkeys and richer session management
