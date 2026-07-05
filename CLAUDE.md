# Whisperdown

macOS SwiftUI voice recorder that transcribes locally (whisper.cpp, Apple Speech fallback) and saves recordings as Markdown notes.

## Build — two paths, BOTH must compile

1. `swift build` — SPM, `swift-tools-version: 6.0`, **Swift 6 strict concurrency**.
2. `bash Scripts/build-app.sh` — raw swiftc glob of `Sources/Whisperdown/*.swift` into `.build/Whisperdown.app`. Runs in **Swift 5 language mode** (no `-swift-version 6`).

Consequences:
- Every change must pass both gates. New `.swift` files under `Sources/Whisperdown/` are picked up automatically by both (SPM target + glob); no manifest edits needed.
- Bare-slash regex literals (`/.../`) compile under SPM but FAIL in `build-app.sh`. Use extended delimiters: `#/.../#`.
- Closures crossing into `Task`/escaping contexts need explicit `@escaping` even with `@Sendable` typing.

Run the app: `open .build/Whisperdown.app` (quit first with `osascript -e 'quit app "Whisperdown"'` to pick up a rebuild).

Design snapshots (visual QA without running the app):
`bash Scripts/render-design-snapshot.sh <output.png> <light|dark> <empty|ready|processing|recording|failed> [width] [height]`
Scenario data lives in `DesignPreview.swift` (`DesignPreviewData`); it constructs `DetailView`/`SidebarView` directly, so **any change to their memberwise initializers must also update `DesignPreview.swift`**.

## Git workflow

- **Never push directly to `main`.** Branch → PR → **squash merge**.
- **All commit messages and PR titles/bodies in English.**

## Architecture

- `RootView` owns the `@StateObject`s (`RecordingStore`, `AudioRecorder`, `RecordingProcessor`, `AudioPlaybackController`, `SummaryCoordinator`) and threads state down as **plain props** — no `@EnvironmentObject` anywhere; keep it that way.
- `TranscriptionEngine` (facade) → `WhisperCppTranscriptionEngine` if configured, else `AppleSpeechTranscriptionEngine` (ko_KR, on-device when supported). Engines are plain `Sendable` structs that shell out via `Process`.
- whisper.cpp pipeline: ffmpeg → 16kHz mono PCM wav → whisper-cli (`-l ko`, txt+JSON output) → validation (empty check + hallucination filter using token probabilities from the JSON).
- `RecordingProcessor` (`@MainActor ObservableObject`) drives the flow and writes Markdown via `MarkdownWriter`; titles from `TitleExtractor`.
- **Callback pattern for engine→UI reporting**: parameters typed `@MainActor @Sendable (T) -> Void` (e.g. `onStageChange`, `onProgress`). This lets Sendable structs call into the MainActor processor with a plain `[weak self]` closure — no `Task { @MainActor in }` wrapping. Follow this pattern for any new engine→UI channel.
- `TranscriptionStage` (converting/transcribing/finalizing) is **transient display state** — never persist it. `RecordingStatus` (`.ready/.processing/.failed`) is the persisted, `Codable` model in `Models.swift`; don't mix the two.
- **FoundationModels isolation**: `import FoundationModels` lives ONLY in `FoundationModelsSummarizer.swift`, fully wrapped in `#if canImport(FoundationModels)` + `@available(macOS 26.0, *)`. Deployment target stays macOS 14 (weak link). Never let FM types leak into other files — everything else talks through `SummaryBackend`/`SummaryAvailability` in `SummaryEngine.swift`. Background summary tasks live in `SummaryCoordinator` (keyed by `Recording.ID`), NOT in `RecordingProcessor` (its defer resets all @Published state on return).
- Summary writes replace only the `## 요약` section body (`MarkdownWriter.replacingSummarySection`) — never full re-render onto an existing file (would clobber manual edits). `GLOSSARY.md` in the markdown folder is read fresh on every summarize run and injected into the model instructions (capped at 1,200 chars).
- **FoundationModels language-detector quirk (learned from a real 47-min meeting)**: the on-device model throws `unsupportedLanguageOrLocale` ("Unsupported language") on chunks dominated by very short disfluent fragments + repeated `Speaker N:` labels — the labels dilute the actual language content past the detector's confidence threshold. Two defenses in `SummaryEngine`, both required: (1) the chunker omits `Speaker N:` labels entirely when there's only ONE distinct speaker; (2) `mapChunk` is per-chunk resilient — on any error it retries once with labels stripped, and if that still fails it skips that chunk (returns nil) rather than aborting the whole summary. Never let one bad chunk kill the summary.

## whisper-cli specifics (homebrew whisper-cpp 1.9.1)

- Binary lookup order: `WHISPERDOWN_WHISPER_CLI` env → bundle → `/opt/homebrew/bin` → `/usr/local/bin`. Same idea for ffmpeg/model (`WHISPERDOWN_FFMPEG`, `WHISPERDOWN_WHISPER_MODEL`).
- Models live in `~/Library/Application Support/Whisperdown/Models/` (shared with `ModelDownloadManager`); preference order large-v3-turbo → large-v3 → medium → small → base.
- GPU is **opt-in** via `WHISPERDOWN_WHISPER_GPU=1`; otherwise `--no-gpu` (CPU safe mode). **When GPU is on, the engine MUST pass `-et 2.8`** — measured on a real 47-min recording: default-flag Metal decoding fell into a repetition loop at the 15-min mark and destroyed the remaining 32 minutes (same sentence 1,389×); disabling flash-attn didn't fix it, raising the entropy threshold 2.4→2.8 did (verified twice, byte-identical output, 2.5 min vs 21.5 min CPU — 8.4× faster).
- Progress: `-pp` prints `whisper_print_progress_callback: progress =  NN%` to **stderr**, once per 30-second audio chunk, and works alongside `-np`. Quirk: clips under 30s can emit a single value **over 100%** (observed 375%) — always clamp to 0...1. Short recordings therefore show no mid-flight percent; that's expected.
- `run()` streams both pipes concurrently with `bytes.lines` (prevents 64KB pipe-buffer deadlock) while accumulating full output for `WhisperCppError.processFailed`.

## Localization (L10n)

- All UI strings go through `L10n.t(key, language)` — a flat `[String: [AppLanguage: String]]` table in `L10n.swift`, grouped by `// MARK:` sections, dot-namespaced keys (e.g. `stage.transcribing.eta`). Always add both `.en` and `.ko`.
- Views read the language via `@Environment(\.appLanguage)`; non-View layers (engines, processor, errors) use the static `AppLanguage.current` (UserDefaults-backed).
- No string catalogs / .strings files — keep the flat table.

## Dev hooks (environment variables)

- `WHISPERDOWN_ONBOARDING_STEP=welcome|diagnostics|modelPicker` — force an onboarding step on launch.
- `WHISPERDOWN_AUTODOWNLOAD=<model fileName>` — auto-start a model download.
- `WHISPERDOWN_WHISPER_CLI=/nonexistent` — force the Apple Speech fallback path for testing.
