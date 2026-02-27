# SayIt (macOS)

Swift-native macOS dictation app:
- realtime STT (faster_whisper only)
- refine (Codex OAuth or OpenAI API)
- history, search, export (TXT/MD/JSON)
- local model manager
- menu tray + global hotkey
- CLI + desktop app

## Requirements

- macOS 14+
- Xcode with Swift 6 toolchain

## Build

```bash
swift build --product SayItApp
swift build --product sayit
```

## Run

```bash
swift run SayItApp
```

CLI:

```bash
swift run sayit --help
```

## First-time setup

1. Open **Settings** tab.
2. Configure default pipeline and edit stages in **Text Pipeline Editor**.
3. Grant microphone permission when prompted.

Notes:
- STT is fixed to `faster_whisper`.

## Realtime usage

- Click **Start** in Live tab (or hotkey `Cmd+Shift+Space`).
- Partial text appears first, final segments are stored to history.
- You can transcribe existing audio files from **Transcribe File** in Live tab.
- Click **Refine** or **Speak** for post-processing and TTS.
- History tab now supports audio assets: play original audio and retranscribe into a new session.

## Local STT

Optional env for local realtime chunking:
- `SAYIT_LOCAL_STREAM_CHUNK_SEC` (default `0.8`, range `0.3`-`10.0`)

Faster-Whisper provider runs local command transcription with chunked recording:
- default model: `small`
- default executables probe order: `SAYIT_FASTER_WHISPER_PYTHON` (if set), then `python3`
- optional env:
  - `SAYIT_FASTER_WHISPER_MODEL` (for example `small`, `base`, `medium`)
  - `SAYIT_FASTER_WHISPER_PYTHON` (absolute python path, for example venv python)
  - `SAYIT_FASTER_WHISPER_COMMAND` (full command template with placeholders `{input}` and `{lang}`)
  - `SAYIT_LOCAL_COMMAND_TIMEOUT_SEC` (default `900`, useful for first-time model pull)

Live mode behavior with `faster_whisper`:
- during recording: captures full session audio
- after pressing stop: runs one-shot transcription and shows processing progress

Settings -> Local Models:
- provides `faster_whisper` runtime setup (install runtime / preload small model / diagnose)

Example command template (same flow as diagnostic-audio then parse with faster-whisper):
```bash
export SAYIT_FASTER_WHISPER_COMMAND="'/root/.openclaw/workspace/.venv-stt/bin/python' - <<'PY' {input} {lang}
import sys
from faster_whisper import WhisperModel

audio = sys.argv[1]
language = sys.argv[2].strip()
if language in ('', 'auto'):
    language = None

model = WhisperModel('small', device='cpu', compute_type='int8')
segments, _ = model.transcribe(audio, beam_size=3, vad_filter=True, language=language)
for seg in segments:
    text = (seg.text or '').strip()
    if text:
        print(f'[{seg.start:6.2f}-{seg.end:6.2f}] {text}')
PY"
```

No built-in model download is required when using external `faster_whisper`.

## CLI quick examples

```bash
swift run sayit listen --provider faster_whisper --locale zh-Hans --seconds 20
swift run sayit transcribe --input /tmp/sample.m4a --locale zh-Hans --provider faster_whisper --fallback faster_whisper
echo "raw text" | swift run sayit refine --provider codex
swift run sayit pipeline list
swift run sayit pipeline export-defaults --output ./pipelines.json
swift run sayit pipeline import --file ./pipelines.json
swift run sayit providers test
swift run sayit auth status-codex
swift run sayit auth login-codex
swift run sayit auth import-codex
```
