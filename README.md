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

## Build from Source

```bash
git clone https://github.com/Keith-CY/sayit.git
cd sayit
open SayIt.xcodeproj
```

Or run from CLI:

```bash
xcodebuild -project SayIt.xcodeproj -scheme SayIt -destination 'platform=macOS' build
```

## Privacy

Audio, transcripts, and clipboard content are processed locally and are not uploaded.

## Contributing

Pull requests are welcome. Keep changes focused, and update docs when behavior changes.

## License

- Before 2026-02-23: Apache 2.0
- On/after 2026-02-23: [GNU General Public License v3.0 (GPLv3)](LICENSE)
