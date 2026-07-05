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

## AI summary (optional, on-device)

The `## 요약` section is filled by Apple Foundation Models (the on-device Apple Intelligence LLM, macOS 26+) after transcription completes — **in the background**, so the transcript appears immediately and the summary lands as a second write.

- **GLOSSARY.md**: a user-editable file in the Markdown output folder, injected into the model instructions on every run (live edits apply to the next summary). Terms listed there let the model fix words the transcriber misheard and apply domain context — verified empirically: a transcript containing the mis-transcription "스프린 트" was summarized with the corrected term "스프린트" from a glossary entry.
- **Chunked map-reduce**: the on-device model has a 4,096-token window (~10 minutes of Korean speech). Longer transcripts are split at segment/sentence boundaries (~2,000-char chunks), summarized per chunk, then combined; a context-overflow error halves the chunk budget and retries once.
- **Targeted write**: only the `## 요약` section body is replaced in the existing file (line-scan, no full re-render) — manual edits elsewhere survive, front matter untouched. If the user deleted the heading, the file is left alone and the summary is stored only in index.json.
- **Isolation**: `import FoundationModels` lives in exactly one file (`FoundationModelsSummarizer.swift`), fully wrapped in `#if canImport` + `@available(macOS 26.0, *)` — the deployment target stays macOS 14; on older systems the feature is hidden and Settings shows "Requires macOS 26".
- **Note**: summary is a *presentation layer on top of* the raw transcript — the `## 전사` section and `Recording.transcript` remain whisper's verbatim output, per the validation-not-correction policy above. Failure of the summary never affects the transcription (quiet inline notice + retry button).

### Local model summary backend (optional, high-performance)

Beyond the Apple default, Settings offers a **llama.cpp sidecar** running Gemma 4 GGUF models (E4B 5GB/128K ctx, 12B 7.1GB/256K, 26B-A4B MoE 17GB/256K — unsloth Q4_K_M). Each model row shows an LM-Studio-style hardware-fit badge (recommended / may be slow / not enough memory) computed from this Mac's unified memory vs the model's requirement; insufficient models can't be downloaded or selected.

- **No chunking**: local backends advertise a 60k-char context budget via `SummaryBackend.contextCharBudget`, so even multi-hour transcripts summarize in a single pass (the chunker naturally yields one chunk). The glossary budget also grows to 4,000 chars.
- **Invocation** (empirically pinned): `llama-completion -m <gguf> -f <promptfile> --jinja --no-display-prompt --temp 0.2 -c 65536 -n 4096 --no-warmup` — note recent llama.cpp split raw completion out of `llama-cli` (whose chat UI pollutes stdout). Gemma 4 is a thinking model: stdout carries a thought block, and the final answer is extracted after the last `<channel|>` marker.
- **Silent fallback**: if the selected local model or runtime is missing at summarize time, the Apple backend is used — selection lives in UserDefaults (`summaryBackend`, `summaryModelFileName`).
- **Install**: in-app (runtime ~11MB + chosen GGUF) or `Scripts/install-llama.sh`. Layout: `~/Library/Application Support/Whisperdown/Summary/{llama.cpp/bin, Models/}`; env overrides `WHISPERDOWN_LLAMA_CLI`, `WHISPERDOWN_SUMMARY_MODEL`.

### Post-correction candidates (currently absent)

- **Punctuation/spacing correction** — Korean post-processing model or LLM pass over the transcript body itself.

## Related files

- `Sources/Whisperdown/WhisperCppTranscriptionEngine.swift` — whisper-cli invocation, progress/stage signals, validation
- `Sources/Whisperdown/AppleSpeechTranscriptionEngine.swift` — fallback path
- `Sources/Whisperdown/LiveSpeechTranscriptionSession.swift` — live preview during recording
- `Sources/Whisperdown/SpeakerDiarizationEngine.swift` — sherpa-onnx sidecar invocation and turn parsing
- `Sources/Whisperdown/SpeakerTurnMerger.swift` — token/turn merge algorithm
- `Sources/Whisperdown/SummaryEngine.swift` — summary facade, chunker, prompt builder, `SummaryBackend` protocol
- `Sources/Whisperdown/FoundationModelsSummarizer.swift` — isolated Apple Foundation Models backend
- `Sources/Whisperdown/SummaryCoordinator.swift` — background summary tasks, targeted `## 요약` write
- `Sources/Whisperdown/ModelCatalog.swift` + `DiarizationCatalog.swift` — downloadable item lists
- `Sources/Whisperdown/MarkdownWriter.swift` — output templating (no content transformation)
- `Sources/Whisperdown/TitleExtractor.swift` — title heuristic
