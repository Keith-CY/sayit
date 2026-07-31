# SayIt

SayIt is a macOS dictation app with local speech-to-text input for any text field.

Download: [latest release](https://github.com/Keith-CY/sayit/releases/latest)

## Highlights

- Global hotkey to start/stop recording.
- System tray / menu bar control with lightweight waveform status.
- Live dictation preview.
- Multiple local speech backends (Apple Speech, Whisper, Parakeet).
- Direct paste into the active app after transcription.
- Optional AI post-processing for refined text output.

## Requirements

- macOS 14.0+
- Microphone permission
- Accessibility permission (for global typing)

## Quick Start

1. Download and open SayIt from releases.
2. Grant the required permissions.
3. Open **Settings** and set a hotkey.
4. Press the hotkey to start/stop recording.
5. Confirm the transcribed text and send.

## Recommended Chinese + English Setup

For Chinese dictation that includes English names, product terms, or technical phrases:

1. Open `Settings` -> `Voice Engine`.
2. Set `Speech Language` to `中文 + English (Mixed)`.
3. SayIt selects Whisper Medium automatically. The first use downloads about 1.5 GB.
4. Keep AI Enhancement off for literal transcription, or enable it only when you want cleanup.

Mixed mode uses Whisper's automatic language recognition for the whole utterance. Results still depend on pronunciation, microphone quality, and the model; it is not a guarantee that every embedded English word will be preserved.

## OpenAI-Compatible Providers

SayIt supports OpenAI v1-compatible APIs, including local providers like llama.cpp, Ollama, and LM Studio.

1. Open `Settings` -> `AI Enhancements`.
2. Pick one of:
   - `llama.cpp` (default: `http://127.0.0.1:8080/v1`)
   - `Ollama` (default: `http://localhost:11434/v1`)
   - `LM Studio` (default: `http://localhost:1234/v1`)
   - `OpenAI-Compatible` (default: blank; you must set a base URL)
3. Set the provider base URL if needed.
4. Refresh models.
   - For local endpoints, SayIt will also auto-fetch models when you select the provider.
   - If `/v1/models` is unavailable on local endpoints, SayIt falls back to `/api/tags` (Ollama-style).
5. Select a model and verify connection.
6. Enable `AI Enhancement` only if you want transcription cleanup.

Notes:
- `llama.cpp` connects directly to `llama-server`. Change the base URL when you launch it on a non-default port.
- Empty base URLs are treated as misconfigured and calls fail fast with a clear error.
- Built-in providers now support per-provider base URL overrides.
- Local API keys are optional, but are sent when configured (useful for authenticated LAN proxies).
- If optional cleanup fails or returns empty text, SayIt uses the original transcription instead of typing an error message.
- The default cleanup prompt preserves Chinese/English code-switching and does not translate.

## Build from Source

```bash
git clone https://github.com/Keith-CY/sayit.git
cd sayit
open SayIt.xcodeproj
```

Or run from CLI:

```bash
./build.sh
LAUNCH_APP=1 ./build.sh
```

## Privacy

Speech recognition runs locally. When AI Enhancement is disabled, transcription is not sent to an AI provider.

When AI Enhancement is enabled, the transcript and cleanup prompt are sent to the provider URL you selected. A local Ollama/LM Studio endpoint keeps that request on your machine or LAN; a cloud endpoint uploads it to that provider. Clipboard copies and local transcription history follow their separate settings.

## Contributing

Pull requests are welcome. Keep changes focused, and update docs when behavior changes.

## License

- Before 2026-02-23: Apache 2.0
- On/after 2026-02-23: [GNU General Public License v3.0 (GPLv3)](LICENSE)
