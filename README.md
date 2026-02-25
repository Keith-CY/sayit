# SayIt (macOS)

Swift-native macOS dictation app:
- realtime STT (OpenAI primary)
- local fallback providers (Whisper + Parakeet + Moonshine, all in-process; Moonshine is compatibility mode)
- refine (Codex OAuth or OpenAI API)
- history, search, export (TXT/MD/JSON)
- local model manager with resume download (`.part`) + optional sha256 verification
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
2. Fill `OpenAI API Key` and click save.
3. (Optional) Use **Codex OAuth Login** section to run device-auth login and auto-import tokens.
4. Configure default pipeline and edit stages in **Text Pipeline Editor**.
5. Grant microphone permission when prompted.

## Realtime usage

- Click **Start** in Live tab (or hotkey `Cmd+Shift+Space`).
- Partial text appears first, final segments are stored to history.
- You can transcribe existing audio files from **Transcribe File** in Live tab.
- Click **Refine** or **Speak** for post-processing and TTS.
- History tab now supports audio assets: play original audio and retranscribe into a new session.

## Local providers

Optional env for local realtime chunking:
- `SAYIT_LOCAL_STREAM_CHUNK_SEC` (default `2.5`, range `1.0`-`10.0`)

Whisper provider runs fully in-process via `whisper.cpp` (Swift package integration), no external shell command required.
Default model path:
- `~/Library/Application Support/SayIt/models/whisper/ggml-base.bin`

Optional env:
- `SAYIT_WHISPER_MODEL_PATH` (override model file path)

Parakeet provider runs in-process via `FluidAudio` CoreML runtime:
- default behavior: auto-download/load models on first use
- optional env: `SAYIT_PARAKEET_COREML_PATH` (preloaded CoreML model directory for offline/manual loading)

Moonshine provider currently uses in-process compatibility runtime:
- tries Parakeet CoreML runtime first
- falls back to local Whisper runtime when Parakeet is unavailable

Local Models panel:
- `whisper` download is used directly by Whisper runtime
- `parakeet/moonshine` downloads are raw archives for native-runtime preparation and inspection

## CLI quick examples

```bash
swift run sayit listen --provider openai --locale zh-Hans --seconds 20
swift run sayit transcribe --input /tmp/sample.m4a --locale en --provider openai --fallback whisper
echo "raw text" | swift run sayit refine --provider codex
swift run sayit pipeline list
swift run sayit pipeline export-defaults --output ./pipelines.json
swift run sayit pipeline import --file ./pipelines.json
swift run sayit models list --json
swift run sayit models inspect
swift run sayit models inspect --json
swift run sayit models verify
swift run sayit models verify --json
swift run sayit models cleanup --all
swift run sayit models cleanup --all --json
swift run sayit models retry --name ggml-base.bin
swift run sayit providers test
swift run sayit auth status-codex
swift run sayit auth login-codex
swift run sayit auth import-codex
```
