# Livescript

Livescript is a macOS floating live transcription app for meetings and videos.

It captures microphone audio and system audio (Zoom, Google Meet, browser, YouTube, etc.), transcribes in real time with WhisperKit on-device, and lets you export transcripts locally.

## Current Features

- Floating always-on-top transcript window
- Best-effort window capture exclusion (`NSWindow.sharingType = .none`)
- Audio source modes:
  - `Mic`
  - `System`
  - `Mixed`
- On-device Whisper transcription with automatic language detection (Chinese/English/mixed)
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
- WhisperKit (ASR)
- SpeakerKit (speaker diarization groundwork)

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode 15+

## Setup

1. Open `Livescript.xcodeproj` in Xcode.
2. Select scheme `Livescript`.
3. Build and run.

Dependencies are managed through Swift Package Manager in the Xcode project.

## Permissions

Livescript needs:

- **Microphone** permission
- **Screen & System Audio Recording** permission (for system audio mode)

If system audio still shows denied after enabling in Settings:

1. Quit the app fully.
2. In **System Settings > Privacy & Security > Screen & System Audio Recording**, remove/re-toggle `Livescript`.
3. Relaunch app and start capture again.

## Usage

1. Click **Start**.
2. Choose a folder for session data.
3. Select source mode (`Mic`, `System`, or `Mixed`).
4. Watch live transcript in the floating window.
5. Export using **Export > TXT** or **Export > Markdown**.

## Notes on Accuracy and Latency

- The app currently uses a low-latency chunking pipeline for faster visible updates.
- In mixed mode, a mic bleed filter suppresses likely speaker echo from laptop speakers.
- For best `You` vs `System` separation, use headphones.

## Project Structure

- `Livescript/ContentView.swift` - main floating UI
- `Livescript/ViewModels/TranscriptionViewModel.swift` - app orchestration and streaming pipeline
- `Livescript/Services/AudioCaptureCoordinator.swift` - mic/system audio capture
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

- Runtime model profile picker (speed vs quality)
- More robust speaker diarization surfaced in UI
- Additional export formats (`json`, `srt`)
- Hotkeys and richer session management