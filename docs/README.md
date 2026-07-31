## SayIt Documentation

This folder contains reference notes for future work.

- `build.sh` performs a pinned, non-signing Debug build by default. Set `LAUNCH_APP=1` to open the result.
- `build_incremental.sh` is the shorthand for the same safe incremental build.
- Add architecture or testing notes here only when they materially affect implementation.
- Keep documentation concise and aligned with current source behavior.

## Provider Compatibility Notes

- `llama.cpp` is a built-in local provider for `llama-server`; its default base URL is `http://127.0.0.1:8080/v1` and can be overridden.
- `OpenAI-Compatible` is a built-in provider for any OpenAI v1-style endpoint.
- Built-in providers support per-provider base URL overrides through settings storage.
- Local model discovery uses `/v1/models` first and falls back to `/api/tags` for Ollama-style servers.
- AI calls fail fast when provider base URL is empty.
- Local endpoints may omit an API key; if one is configured, it is still sent for authenticated local/LAN gateways.
- Optional dictation cleanup falls back to the raw transcript on provider failure or empty output.
- `中文 + English (Mixed)` routes speech recognition to Whisper automatic language detection.
