# Livescript

**Language / 语言:** [English](#english) · [中文](#中文)

---

<a id="english"></a>

## English

> **Live captions on your Mac — free, private, and fast.**  
> Floating real-time transcription for meetings and videos. No cloud. No subscription. Your audio stays on your device.

Capture **microphone** and **system audio** (Zoom, Google Meet, browser, YouTube, and more), transcribe on-device in **English or Chinese**, and export transcripts locally.

### Why Livescript?

| | |
|---|---|
| **Free transcription** | No API keys, no usage fees, no account. Download models once and transcribe as much as you want. |
| **Local privacy** | Audio is processed entirely on your Mac. Nothing is uploaded to the cloud for ASR. |
| **Low latency** | Smart profile delivers draft captions in ~0.5–1.5s, with quality refine on natural pauses. |
| **High accuracy** | Draft → refine pipeline: fast SenseVoice draft, then distil-large-v3 (EN) or SenseVoice (ZH) on pause. |
| **Meeting-ready** | Stealth mode hides the window from screen sharing. Mixed mode labels **You** vs **System**. |
| **Bilingual** | Automatic English / Chinese detection and routing — built for bilingual meetings. |

### Highlights

- Floating always-on-top window with smart auto-scroll
- **Smart** profile (default): Zoom-style draft → refine captions
- Source modes: **Mic**, **System**, **Mixed**
- Stealth toggle (on by default) — hidden from screen capture
- Export **TXT** / **Markdown**; session checkpointing for long meetings
- 32 unit tests covering the transcription pipeline

### Quick Start

```bash
# 1. Download models (one time)
./scripts/download_all_models.sh

# 2. Build the app
./scripts/build_release_local.sh

# 3. Install (optional)
./scripts/install_release_local.sh
```

Then open Livescript, click **Start**, choose a session folder, pick **Source** and **Speed**, and read live captions.

### Speed Profiles

| Profile | Best for | Typical lag |
|---------|----------|-------------|
| **Smart** (default) | Live meetings — fast draft + accurate refine | draft ~0.5–1.5s · refine ~2–3.5s |
| **Balanced** | Good accuracy, moderate speed | ~2–3s |
| **Quality** | Maximum accuracy | ~4–6s |

**Smart captions flow:** while someone speaks, text updates every ~1s; on ~400ms pause, the full utterance is refined and replaces the draft in place. English refine uses **distil-large-v3**; Chinese refine uses **SenseVoice**.

### Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode 15+ (to build from source)

### Models

Models live under **`~/workspace/models/`** (override with `LIVESCRIPT_MODELS_DIR`):

```
~/workspace/models/
├── sensevoice/          # Smart draft + Chinese refine
├── punctuation/         # Optional English punctuation
├── vad/                 # Optional VAD
└── models/              # WhisperKit (distil-large-v3, small, large-v3)
```

Download: `./scripts/download_all_models.sh`

### Build Options

| Command | What it does |
|---------|--------------|
| `./scripts/build_release_local.sh` | Download models + Release build → `dist/Livescript.app` |
| `./scripts/install_release_local.sh` | Test, build, install to `/Applications`, launch |
| `./scripts/package_dmg_local.sh` | Create `dist/Livescript-local.dmg` |

### Permissions (first run)

- **Microphone** — for Mic / Mixed
- **Screen & System Audio Recording** — for System / Mixed
- **Files and Folders** — when choosing session / model directories

### Usage

1. Run `./scripts/download_all_models.sh` once.
2. Click **Start** and choose a session folder.
3. Set **Source** (`Mic` / `System` / `Mixed`) and **Speed** (`Smart` recommended).
4. Toggle **Stealth** if you need the window visible in screen share.
5. **Export > TXT** or **Export > Markdown** when done.

### Tech Stack

SwiftUI · AVFoundation · ScreenCaptureKit · **WhisperKit** · **sherpa-onnx** (SenseVoice)

### Tests

```bash
./scripts/run_unit_tests.sh   # 32 tests
```

### Known Limitations

- Screen capture exclusion is best-effort.
- Transcription supports **English and Chinese** only.
- Speaker labels are source-based (`You` / `System`), not person-level diarization.
- Export includes refined segments only.

See [TECH_DESIGN.md](TECH_DESIGN.md) for architecture details.

---

<a id="中文"></a>

## 中文

> **Mac 上的实时字幕 — 免费、私密、低延迟。**  
> 会议与视频的悬浮实时转写。无需云端，无需订阅，音频始终留在本机。

同时采集**麦克风**与**系统音频**（Zoom、Google Meet、浏览器、YouTube 等），在设备端完成**中英文**实时转写，并本地导出文稿。

### 为什么选择 Livescript？

| | |
|---|---|
| **完全免费** | 无需 API Key、无按量计费、无需账号。模型下载一次，即可无限转写。 |
| **本地隐私** | 音频仅在 Mac 上处理，ASR 不上传云端。 |
| **低延迟** | Smart 模式草稿约 0.5–1.5 秒出字，停顿后自动精修。 |
| **高准确率** | 草稿 → 精修：SenseVoice 快速出稿，停顿时 distil-large-v3（英文）或 SenseVoice（中文）整句重解码。 |
| **会议友好** | Stealth 隐身模式默认开启，屏幕共享时尽量隐藏窗口；Mixed 模式区分 **You** / **System**。 |
| **中英双语** | 自动检测语言并路由到对应精修引擎，适合双语会议。 |

### 功能亮点

- 始终置顶的悬浮窗，智能自动滚动
- **Smart** 模式（默认）：类 Zoom 的草稿 → 精修字幕
- 音源：**Mic**、**System**、**Mixed**
- **Stealth** 开关（默认开启）— 尽量不被录屏捕获
- 导出 **TXT** / **Markdown**；长会议会话 checkpoint
- 32 项单元测试覆盖转写流水线

### 快速开始

```bash
# 1. 下载模型（一次性）
./scripts/download_all_models.sh

# 2. 构建应用
./scripts/build_release_local.sh

# 3. 安装并启动（可选）
./scripts/install_release_local.sh
```

打开 Livescript，点击 **Start**，选择会话目录，设置 **Source** 与 **Speed**，即可看到实时字幕。

### 速度档位

| 档位 | 适用场景 | 典型延迟 |
|------|----------|----------|
| **Smart**（默认） | 实时会议 — 快草稿 + 准精修 | 草稿 ~0.5–1.5s · 精修 ~2–3.5s |
| **Balanced** | 速度与准确率平衡 | ~2–3s |
| **Quality** | 最高准确率 | ~4–6s |

**Smart 流程：** 说话时约每秒更新草稿；约 400ms 停顿时，对整句（最长 8s）精修并原地替换草稿。英文精修用 **distil-large-v3**，中文精修用 **SenseVoice**。

### 系统要求

- macOS 14+
- 推荐 Apple Silicon
- 从源码构建需 Xcode 15+

### 模型目录

模型默认位于 **`~/workspace/models/`**（可用 `LIVESCRIPT_MODELS_DIR` 覆盖）：

```
~/workspace/models/
├── sensevoice/          # Smart 草稿 + 中文精修
├── punctuation/         # 可选英文标点
├── vad/                 # 可选 VAD
└── models/              # WhisperKit（distil-large-v3、small、large-v3）
```

下载命令：`./scripts/download_all_models.sh`

### 构建方式

| 命令 | 说明 |
|------|------|
| `./scripts/build_release_local.sh` | 下载模型 + Release 构建 → `dist/Livescript.app` |
| `./scripts/install_release_local.sh` | 测试、构建、安装到 `/Applications` 并启动 |
| `./scripts/package_dmg_local.sh` | 生成 `dist/Livescript-local.dmg` |

### 首次权限

- **麦克风** — Mic / Mixed 模式
- **屏幕与系统音频录制** — System / Mixed 模式
- **文件与文件夹** — 选择会话 / 模型目录时

若系统音频权限异常：完全退出应用，在系统设置中重新开关 Livescript 的录屏权限后重启。

### 使用步骤

1. 一次性运行 `./scripts/download_all_models.sh`。
2. 点击 **Start** 并选择会话文件夹。
3. 设置 **Source**（Mic / System / Mixed）与 **Speed**（推荐 Smart）。
4. 若需在共享屏幕中显示窗口，可关闭 **Stealth**。
5. 结束后通过 **Export > TXT** 或 **Export > Markdown** 导出。

### 技术栈

SwiftUI · AVFoundation · ScreenCaptureKit · **WhisperKit** · **sherpa-onnx**（SenseVoice）

### 测试

```bash
./scripts/run_unit_tests.sh   # 32 项测试
```

### 已知限制

- 屏幕捕获隐藏为尽力而为，取决于第三方共享工具。
- 转写仅支持**英文与中文**。
- 说话人标签基于音源（You / System），非说话人级 diarization。
- 导出仅包含已精修片段。

架构细节见 [TECH_DESIGN.md](TECH_DESIGN.md)。
