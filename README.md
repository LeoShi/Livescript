# Livescript

Livescript is a macOS floating live transcription app for meetings and videos.

It captures microphone audio and system audio (Zoom, Google Meet, browser, YouTube, etc.), transcribes in real time on-device, and lets you export transcripts locally.

## Current Features

- Floating always-on-top transcript window
- Best-effort window capture exclusion (`NSWindow.sharingType = .none`)
- Audio source modes:
  - `Mic`
  - `System`
  - `Mixed`
- On-device transcription with automatic language detection (Chinese/English/mixed)
- **Smart** profile (default): SenseVoice draft + distil-large-v3 refine on pause (Zoom-style captions)
- **Balanced/Quality** profiles: single-pass Whisper chunks
- Local-first model loading, with fallback model download
- Real-time model preparation/download status in UI
- Speaker labeling for mixed input (`You` / `System`)
- Selectable transcript text (multi-line selection)
- Speaker-aware transcript rendering:
  - Repeated speaker labels are hidden when unchanged
  - Colorized speaker labels for readability
- Transcript export formats:
  - `.txt`
  - `.md`
- Session checkpointing for long-running meetings

## Tech Stack

- SwiftUI
- AppKit (`NSPanel`, `NSTextView` integration)
- AVFoundation (microphone capture)
- ScreenCaptureKit (system audio capture)
- WhisperKit (Balanced/Quality ASR)
- sherpa-onnx + SenseVoice-Small (Real-time ASR)
- SpeakerKit (speaker diarization groundwork)

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode 15+

## Unit Tests

Run regression tests for the transcription pipeline (chunk ordering, hallucination filtering, dedup):

```bash
./scripts/run_unit_tests.sh
```

## Local Production Build

### Option A: One-command local release build (recommended)

From repo root:

```bash
./scripts/build_release_local.sh
```

Build output:

- `dist/Livescript.app`

Optional local installer DMG:

```bash
./scripts/package_dmg_local.sh
```

DMG output:

- `dist/Livescript-local.dmg`

### Option B: Build from Xcode

1. Open `Livescript.xcodeproj` in Xcode.
2. Select scheme `Livescript`.
3. Choose **Product > Build For > Running** with `Release` configuration.
4. Locate app from DerivedData and copy it to your desired install location.

Dependencies are managed through Swift Package Manager in the Xcode project.

## Install on Your Mac

### From app bundle

1. Build using `./scripts/build_release_local.sh`.
2. Drag `dist/Livescript.app` to `/Applications` (or `~/Applications`).
3. Launch the app.

### From DMG

1. Create DMG using `./scripts/package_dmg_local.sh`.
2. Open `dist/Livescript-local.dmg`.
3. Drag `Livescript.app` into `Applications`.

## First-run Permissions Checklist

Livescript needs:

- **Microphone** permission
- **Screen & System Audio Recording** permission (for system audio mode)
- **Files and Folders** access when selecting model/session/export directories

If system audio still shows denied after enabling in Settings:

1. Quit the app fully.
2. In **System Settings > Privacy & Security > Screen & System Audio Recording**, remove/re-toggle `Livescript`.
3. Relaunch app and start capture again.

If microphone capture fails:

1. Open **System Settings > Privacy & Security > Microphone**.
2. Ensure `Livescript` is enabled.
3. Relaunch app.

If model setup fails:

1. Verify the selected model folder exists and is readable.
2. If using fallback download, verify internet connectivity.
3. Re-select model folder in app and restart.

## Usage

1. Click **Start**.
2. Choose a folder for session data.
3. Select source mode (`Mic`, `System`, or `Mixed`).
4. Watch live transcript in the floating window.
5. Export using **Export > TXT** or **Export > Markdown**.

## Operational Notes

- Local distribution in this repo is for your own Mac usage.
- App is not notarized in this workflow, so Gatekeeper prompts may appear depending on how it is launched.
- Current release metadata:
  - Marketing version: `1.0.0`
  - Build number: `2`

## Notes on Accuracy and Latency

Latency is dominated by the ASR engine and model size, not UI code. Use the **Speed** picker in the app header:

| Profile | Engine | Models | Behavior | Typical lag |
|---------|--------|--------|----------|-------------|
| **Smart** (default) | SenseVoice + Whisper | draft: SenseVoice-Small, refine: distil-large-v3 | Draft hops every 1.5s, refine on pause | draft ~0.5–1.5s, refine ~2–3.5s |
| **Balanced** | Whisper | `small` | 2s chunks | ~2–3s |
| **Quality** | Whisper | `large-v3` | 2s chunks | ~4–6s |

All models live under `~/workspace/models/` (override with `LIVESCRIPT_MODELS_DIR`):

```
~/workspace/models/
├── sensevoice/                 # SenseVoice-Small draft, ~228 MB
│   ├── model.int8.onnx
│   └── tokens.txt
├── punctuation/                # Optional ct-punc polish after refine
│   └── model.onnx
├── vad/                        # Silero VAD for Smart utterance boundaries
│   └── silero_vad.onnx
└── models/                     # WhisperKit refine + legacy profiles
    └── argmaxinc/whisperkit-coreml/
        ├── distil-whisper_distil-large-v3/
        ├── openai_whisper-small/
        └── openai_whisper-large-v3-v20240930_626MB/
```

Download everything:

```bash
./scripts/download_all_models.sh
```

Smart captions behavior:

- Gray **draft** lines update every ~1.5s while someone is speaking.
- On pause (~400ms silence), the full utterance is **re-decoded** with distil-large-v3 and replaces the draft in place.
- Optional punctuation pass polishes the refined line.
- In mixed mode, mic bleed from meeting audio is suppressed: overlapping `You` lines that match recent `System` text are dropped, and the mic must be clearly louder than system audio to count as `You`.
- Sound-effect captions like `(keyboard clicking)` and `[BLANK_AUDIO]` are filtered automatically.
- For best `You` vs `System` separation when you also speak, use headphones.

## Project Structure

- `Livescript/ContentView.swift` - main floating UI
- `Livescript/ViewModels/TranscriptionViewModel.swift` - app orchestration and streaming pipeline
- `Livescript/Services/AudioCaptureCoordinator.swift` - mic/system audio capture
- `Livescript/Services/TranscriptionService.swift` - Smart captions (SenseVoice draft + distil-large-v3 refine) and Balanced/Quality Whisper paths
- `Livescript/Services/SenseVoiceTranscriber.swift` - sherpa-onnx SenseVoice-Small decoder
- `Livescript/Services/WhisperTranscriber.swift` - WhisperKit model loading and transcription
- `Livescript/Services/SpeakerDiarizer.swift` - speaker diarization service
- `Livescript/Services/TranscriptExporter.swift` - transcript export logic
- `Livescript/UI/SelectableTranscriptTextView.swift` - selectable rich transcript rendering
- `TECH_DESIGN.md` - detailed technical design doc

## Known Limitations

- Screen capture exclusion is best-effort and depends on macOS/tooling behavior.
- Speaker identity is currently source-based (`You`/`System`) rather than full person-level diarization in UI.
- Export currently writes final text segments only.

## Roadmap Ideas

- More robust speaker diarization surfaced in UI
- Additional export formats (`json`, `srt`)
- Hotkeys and richer session management