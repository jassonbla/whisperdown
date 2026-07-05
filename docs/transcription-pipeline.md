# Transcription Pipeline — Concepts and Components

This document explains what actually runs when a recording is transcribed: which pieces are ML models, which are plumbing, and — importantly — what the pipeline does **not** do to your text.

## The one distinction that matters: engine vs. model

**`whisper-cli` is not a model. It is a runtime.** It is the CLI front-end of [whisper.cpp](https://github.com/ggerganov/whisper.cpp), a C++ reimplementation of OpenAI Whisper *inference*. On its own it recognizes nothing — it loads a GGML weights file and executes it. Think CD player (whisper-cli) vs. CD (the `.bin` model): recognition quality is decided entirely by which model file you load.

## Components and their roles

| Component | Kind | Role |
|---|---|---|
| ffmpeg | tool (not ML) | Normalizes recorded `.m4a` into Whisper's required input: **16 kHz mono PCM wav**. This is the pipeline's "Converting audio" step. |
| whisper-cli | inference runtime | Loads the GGML model, computes the mel spectrogram, runs encoder/decoder inference, writes `.txt` + `.json` output. |
| GGML models (`ggml-*.bin`) | **the actual ML model** | OpenAI Whisper weights converted to GGML format. Stored in `~/Library/Application Support/Whisperdown/Models/`, downloaded from `huggingface.co/ggerganov/whisper.cpp` (see `ModelCatalog.swift`). |
| Apple Speech (`SFSpeechRecognizer`) | OS-provided ASR model | Two separate jobs — see below. |
| `TitleExtractor` | heuristic (not ML) | Takes the first usable line of the transcript, truncated to 28 chars, as the note title. |
| Hallucination filter | heuristic (not ML) | Reads per-token probabilities from whisper's JSON output and rejects known filler phrases ("시청해주셔서 감사합니다" etc.) when confidence is low. Rejects — never rewrites. |

### The GGML model lineup

Preference order in `WhisperCppTranscriptionEngine` (first found wins):

| Model | Size | Notes |
|---|---|---|
| **Large v3 Turbo** (recommended) | 1.6 GB | large-v3 with the decoder distilled from 32 → 4 layers. Near-large accuracy at a fraction of the decode cost. |
| Large v3 | 3.1 GB | Highest accuracy, slowest. |
| Medium / Small / Base | 1.5 GB / 488 MB / 148 MB | Progressively faster and less accurate. |

Whisper is an encoder–decoder transformer. The **encoder** turns 30-second audio chunks (mel spectrogram) into semantic representations; the **decoder** generates text tokens from them autoregressively. Two consequences visible in the app:

- The progress percent (parsed from `-pp` stderr output) advances **once per 30-second chunk** — that is the encoder's work unit. Clips under 30 s emit a single value at the very end, which can exceed 100 % (a known whisper.cpp quirk; the parser clamps to 0...1).
- The token probability (`p`) used by the hallucination filter is the decoder's per-token confidence.

GPU (Metal) is opt-in via `WHISPERDOWN_WHISPER_GPU=1`; the default is CPU safe mode because the Homebrew Metal backend can crash on some Apple Silicon/model combinations.

### Apple Speech's two jobs

1. **Live preview during recording** (`LiveSpeechTranscriptionSession`): microphone buffers are streamed into `SFSpeechRecognizer` for the real-time caption. Whisper cannot do streaming recognition, so this role always belongs to Apple Speech.
2. **Fallback for final transcription**: only when whisper.cpp is not configured (`isConfigured == false`). Locale `ko_KR`, on-device when the recognizer supports it.

So the app effectively uses **two ML systems**: Whisper (final transcription) and Apple Speech (live preview + fallback). Everything else is plumbing around them.

## Pipeline stages (as shown in the UI stepper)

```
recording.m4a
  │
  ▼
[1] Convert          ffmpeg → 16kHz mono PCM wav
[2] Load model       whisper-cli launch → GGML weights into memory
[3] Analyze audio    stderr "main: processing" marker → inference starting
[4] Transcribe       encoder/decoder per 30s chunk; % + ETA + live text preview
[5] Finalize         read .txt/.json, empty check, hallucination filter
  │
  ▼
TitleExtractor → MarkdownWriter → {date}_{title}_추출.md
```

Steps 2–4 are sub-signals inside the whisper-cli process (stderr markers + `-pp` progress + stdout segment text). The Apple Speech path has no such signals, so its stepper shows only 3 steps.

## Speaker diarization (optional sidecar)

When installed, a second subprocess — `sherpa-onnx-offline-speaker-diarization` (pyannote segmentation + NeMo TitaNet speaker embeddings, RTF ≈ 0.05) — runs **in parallel** with whisper-cli on the same 16 kHz wav, answering "who spoke when" while whisper answers "what was said". The stepper gains a "Speaker analysis" row between audio analysis and recognition.

- **Merge**: whisper's full JSON (`-ojf`, already produced) carries per-token millisecond offsets. Each token is assigned to the speaker turn containing its midpoint (largest-overlap for overlapping turns, nearest turn otherwise); consecutive same-turn tokens become one `SpeakerSegment` named "Speaker N" by order of first appearance. A single-speaker result still splits per turn — free paragraphing.
- **Silent-fallback contract**: diarization can never fail or delay a transcription. Any error, empty output, or timeout (60 s cap after whisper finishes) falls back to today's single "Speaker 1" segment and the stepper row shows "skipped". `EngineStatus.isFullyConfigured` (the app-readiness gate) does not include diarization.
- **Text identity**: `Recording.transcript` and the hallucination filter keep using `transcript.txt` verbatim; diarization only shapes the segments array (and thus the Markdown `### Speaker N` sections, whose whitespace may differ from the flat txt).
- **Install**: in-app via onboarding/Settings ("Speaker Separation" section, ≈65 MB), or `Scripts/install-diarization.sh`. Layout: `~/Library/Application Support/Whisperdown/Diarization/` with `sherpa-onnx/{bin,lib}` (rpath-relative, must stay siblings) and `Models/*.onnx`.
- **Env overrides**: `WHISPERDOWN_DIARIZE_CLI`, `WHISPERDOWN_DIARIZE_SEGMENTATION`, `WHISPERDOWN_DIARIZE_EMBEDDING`, `WHISPERDOWN_DIARIZE_THRESHOLD` (clustering threshold, default 0.85; speaker count is auto-detected). Sherpa-onnx's threshold is a merge-distance cutoff, not a similarity cutoff — higher merges more aggressively (fewer speakers), lower fragments more (more speakers). 0.5 was tuned against a clean studio 2-speaker test asset but over-fragmented real close-talk phone-mic recordings (one real recording produced 4 spurious speakers for an actual 2-person conversation); 0.85 was empirically re-validated against that same recording (correct 2 speakers) with headroom before over-merging starts around 1.1.

## Validation vs. post-correction: there is NO post-correction

The transcript text that lands in the Markdown file is **whisper's raw output**, verbatim. The full journey of the text:

1. `transcript.txt` is read and trimmed of leading/trailing whitespace — the only transformation applied, ever.
2. `validateTranscript` is a **gate, not an editor**: it throws (→ `.failed` status) on empty output or low-confidence hallucination phrases. It never modifies content.
3. `MarkdownWriter.render` is pure templating: it wraps the text in a fixed skeleton (YAML front matter, title, date/duration/engine metadata, `## 전사` section with speaker headers). No punctuation fixes, no paragraph splitting, no spacing normalization.

The YAML front matter (`whisperdown: 1`, title, created, duration, audio, engine, speakers, status, generator) is a machine-readable metadata layer for downstream agents reading the output folder. Existing files are migrated once on launch by prepending front matter — the body is never rewritten, so manual edits survive (`RecordingStore.migrateFrontMatterIfNeeded`, idempotent via the `---` prefix check).

One deliberate hook exists for future post-processing: every saved file contains a `## 요약` placeholder section ("자동 요약은 다음 단계에서 연결됩니다") — reserved for an automatic summary step that is not yet implemented.

### Post-correction candidates (all currently absent)

- **Automatic summary** — fill the existing `## 요약` placeholder (local LLM or API).
- **Punctuation/spacing correction** — Korean post-processing model or LLM pass.

(Speaker diarization and turn-based paragraphing shipped with the sherpa-onnx sidecar — see the section above.)

## Related files

- `Sources/Whisperdown/WhisperCppTranscriptionEngine.swift` — whisper-cli invocation, progress/stage signals, validation
- `Sources/Whisperdown/AppleSpeechTranscriptionEngine.swift` — fallback path
- `Sources/Whisperdown/LiveSpeechTranscriptionSession.swift` — live preview during recording
- `Sources/Whisperdown/SpeakerDiarizationEngine.swift` — sherpa-onnx sidecar invocation and turn parsing
- `Sources/Whisperdown/SpeakerTurnMerger.swift` — token/turn merge algorithm
- `Sources/Whisperdown/ModelCatalog.swift` + `DiarizationCatalog.swift` — downloadable item lists
- `Sources/Whisperdown/MarkdownWriter.swift` — output templating (no content transformation)
- `Sources/Whisperdown/TitleExtractor.swift` — title heuristic
