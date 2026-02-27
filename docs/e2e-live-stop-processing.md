# Live End-to-End Checklist (Start -> Stop -> Processing -> Persist)

This checklist verifies the exact path:
- start voice capture
- click stop
- observe processing progress UI
- confirm transcript persistence in sqlite

## 1. Preconditions

1. Build succeeds:
```bash
swift build --product SayItApp
```
2. Open the app:
```bash
swift run SayItApp
```
3. In Settings, ensure:
- STT provider is configured (`openai` or local provider).
- Microphone permission is granted.

## 2. Manual Live Flow

1. Open `Live` tab.
2. Click `Start`.
3. Speak clearly for 3-8 seconds.
4. Click `Stop`.

## 3. Expected UI States

1. During capture:
- status shows `Listening` or `Streaming`.
- mic level animation is active.

2. After stop:
- status switches to `Processing captured audio...` when transcript recovery starts.
- small processing indicator appears.
- determinate progress bar appears with percent and elapsed/total seconds
  (for example `37% (1.9s/5.2s)`).

3. On success:
- status becomes `Saved to history (<provider>)`.
- transcript text is visible in final text area.
- `History` tab contains a new session.

4. On no speech:
- status may become `No speech recognized (<provider>)`.
- no new final segment is expected.

## 4. Persistence Verification

Run:
```bash
scripts/verify_live_session.sh
```

Default source is `app_live_stream`. The script prints:
- latest session row (`closed` expected)
- counts for `segments`, `audio_assets`, `pipeline_runs`
- latest transcript text rows

Expected minimum for a successful run:
- `segments >= 1`
- `audio_assets >= 1`

## 5. Optional CLI Smoke (already proven locally)

This is non-UI but validates transcription + persistence pipeline quickly:
```bash
TMP_AUDIO="/tmp/sayit-e2e-voice.aiff"
say -o "$TMP_AUDIO" "This is a SayIt end to end verification recording."
swift run sayit transcribe --input "$TMP_AUDIO" --provider whisper --fallback whisper --locale en
scripts/verify_live_session.sh "$HOME/Library/Application Support/SayIt/history.sqlite" "cli_file"
```
