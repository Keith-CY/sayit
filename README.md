# SayIt

SayIt is a macOS dictation app with local speech-to-text input for any text field.

Download: [latest release](https://github.com/Keith-CY/sayit/releases/latest)

## Highlights

- Global hotkey to start/stop recording.
- System tray / menu bar control with lightweight waveform status.
- Live dictation preview.
- Multiple local speech backends (Apple Speech, MLX Qwen3-ASR, Whisper, Parakeet).
- Direct paste into the active app after transcription.
- Optional AI post-processing for refined text output.

## Requirements

- macOS 14.0+
- Apple silicon Mac
- Microphone permission
- Accessibility permission (for global typing)

## Quick Start

1. Download and open SayIt from releases.
2. Grant the required permissions.
3. Open **Settings** and set a hotkey.
4. Press the hotkey to start/stop recording.
5. Confirm the transcribed text and send.

Because SayIt is distributed without an Apple Developer account, the first
download is not notarized. Download only from this repository, then
Control-click SayIt and choose **Open**. If macOS still blocks it, use
**System Settings -> Privacy & Security -> Open Anyway**. Do not disable
Gatekeeper globally.

## Recommended Chinese + English Setup

For Chinese dictation that includes English names, product terms, or technical phrases:

1. Open `Settings` -> `Voice Engine`.
2. Set `Speech Language` to `中文 + English (Mixed)`.
3. In the model downloads, select **Qwen3-ASR 1.7B · 8bit** and click **Download** (about 2.47 GB).
4. Once the download finishes, click **Activate**. Downloading alone does not change the active model.
5. Keep AI Enhancement off for literal transcription, or enable it only when you want cleanup.

Qwen uses [mlx-community/Qwen3-ASR-1.7B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit)
on Apple Silicon, with the MLX runtime included in SayIt. No Python installation or
inference server is needed. After downloading, transcription uses local files and
text appears when recording stops. Mixed mode preserves an explicitly selected
Qwen or Whisper model; without that selection, it defaults to Apple Speech
Analyzer on macOS 26+, or Whisper Small on earlier macOS versions.

Recognition still depends on pronunciation, microphone quality, and vocabulary.
Models are stored under `~/Library/Application Support/SayIt/Models/` for Qwen;
an incomplete or damaged download is not offered for activation.

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

## Updates

SayIt 1.6.0 and later can check GitHub Releases from **Preferences -> Software
Updates** or **Check for Updates…** in the menu bar. The app checks once per
day by default, but it never installs without confirmation.

Both the update feed and downloaded archive are verified with SayIt's Sparkle
EdDSA key. Release builds use a stable self-signed macOS identity so updates
retain the same local code identity and privacy grants; they are not signed by
Apple or notarized. Version 1.7.0 is the first published release with this stable
code identity. Updating from 1.6.0 can require granting permissions once more;
subsequent releases retain the same identity.

Maintainer details: [GitHub update and release process](docs/GITHUB_UPDATES.md).

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

The MLX integration requires Swift 6.2 or newer. Install Xcode's Metal compiler
with `xcodebuild -downloadComponent MetalToolchain` if it is not already present.
Both package lockfiles pin the tested dependencies.

The regular Xcode test suite checks model selection, installation completeness,
and the bundled Metal library without downloading weights. To run the real Qwen
transcription test, set `TEST_RUNNER_RUN_QWEN_E2E_TESTS=1` when running `xcodebuild test`.
Optional `TEST_RUNNER_QWEN_E2E_MODEL_DIRECTORY` and `TEST_RUNNER_QWEN_E2E_AUDIO_PATH`
select an existing model directory and a mixed-language audio fixture. The mixed
fixture used for validation says: “请帮我 review 这个 pull request，然后 deploy 到 staging。”

## Privacy

Speech recognition runs locally. When AI Enhancement is disabled, transcription is not sent to an AI provider.

When AI Enhancement is enabled, the transcript and cleanup prompt are sent to the provider URL you selected. A local Ollama/LM Studio endpoint keeps that request on your machine or LAN; a cloud endpoint uploads it to that provider. Clipboard copies and local transcription history follow their separate settings.

## Contributing

Pull requests are welcome. Keep changes focused, and update docs when behavior changes.

## License

- Before 2026-02-23: Apache 2.0
- On/after 2026-02-23: [GNU General Public License v3.0 (GPLv3)](LICENSE)
