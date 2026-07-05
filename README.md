# Whisperdown

Native macOS recording app for turning Korean meeting recordings into Markdown.

## MVP Scope

- SwiftUI macOS app for Apple Silicon.
- One-click recording with `AVFoundation`.
- Audio is stored separately under `Recordings/`.
- Markdown is saved in the user-visible output folder.
- Default output folder: `~/Documents/Whisperdown`.
- Current transcription MVP prefers `whisper.cpp` with Korean language selection.
- Apple Speech is kept only as a fallback when `whisper.cpp` is not configured.
- Optional speaker separation via a sherpa-onnx diarization sidecar (installed in-app or with `Scripts/install-diarization.sh`).
- Optional on-device AI summary (Apple Foundation Models, macOS 26+) that fills the `## 요약` section in the background — guided by a user-editable `GLOSSARY.md` that corrects misheard terms.

## Build

To create a local app bundle:

```bash
Scripts/build-app.sh
```

The app bundle is written to:

```text
.build/Whisperdown.app
```

Swift Package Manager is also configured:

```bash
swift build
```

On this machine, `swift build` may require Xcode license/toolchain setup first. The bundle script uses the installed Xcode toolchain directly.

## Design QA

The UI has a lightweight snapshot renderer for checking the floating sidebar, glass panels, row density, and light/dark contrast without capturing the full desktop.

```bash
Scripts/render-design-snapshot.sh .build/design-snapshot-light.png light ready
Scripts/render-design-snapshot.sh .build/design-snapshot-dark.png dark ready
Scripts/render-design-matrix.sh
```

The renderer uses the real SwiftUI view components with sample recordings, so it is useful for visual regression checks while iterating on the macOS UI. The supported scenarios are `ready`, `processing`, `recording`, `failed`, and `empty`.

## whisper.cpp Setup

The app prefers `whisper.cpp` when `whisper-cli`, `ffmpeg`, and a GGML model are available.

```bash
Scripts/install-whisper-cpp.sh
```

By default the script installs:

- `whisper-cpp` through Homebrew
- `ffmpeg` through Homebrew
- `ggml-large-v3-turbo.bin` under `~/Library/Application Support/Whisperdown/Models/`

You can override paths without changing app code:

```bash
export WHISPERDOWN_WHISPER_CLI=/path/to/whisper-cli
export WHISPERDOWN_FFMPEG=/path/to/ffmpeg
export WHISPERDOWN_WHISPER_MODEL=/path/to/ggml-large-v3-turbo.bin
```

The app currently runs `whisper-cli` in CPU safe mode by default because the Homebrew Metal backend can crash on some Apple Silicon/model combinations. To opt into GPU after local verification:

```bash
export WHISPERDOWN_WHISPER_GPU=1
```

## Transcription Pipeline

See [docs/transcription-pipeline.md](docs/transcription-pipeline.md) for the conceptual breakdown: engine vs. model, component roles, stage signals, the optional diarization sidecar, and the validation-not-correction policy for saved Markdown.

Speaker separation is optional. Install it from onboarding/Settings ("Speaker Separation" section, ≈65 MB) or via:

```bash
Scripts/install-diarization.sh
```

## Planned Transcription Pipeline

1. Record `.m4a` with AVFoundation.
2. Convert audio to whisper-compatible input when needed through `ffmpeg`.
3. Transcribe Korean with `whisper.cpp` when configured.
4. Fall back to Apple Speech only when `whisper.cpp` is missing.
5. Run diarization with a local sidecar.
6. Merge word/segment timestamps with speaker turns.
7. Let the user rename speakers and persist mappings.
8. Generate `{yyyy-MM-dd}_{title}.md` with YAML front matter (machine-readable metadata for downstream agents).

## Storage Layout

```text
Whisperdown/
  2026-07-02_리더십 미팅.md
  Recordings/
    2026-07-02_recording.caf
  .whisperdown/
    index.json
```

Each Markdown file starts with YAML front matter (`whisperdown: 1`, title, created, duration, audio path, engine, speaker count, status) so other tools and agents can parse recordings without reading the app's index.
