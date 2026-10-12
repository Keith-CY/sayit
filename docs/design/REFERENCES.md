# Design References

Observed 2026-10-12. Product URLs returned HTTP 200 on that date. Each entry lists
the practices we compare against and what SayIt must do better. References are for
comparison only; we do not copy layouts, copy or assets.

## Products

**Wispr Flow** — https://wisprflow.ai · https://docs.wisprflow.ai
- HUD: Esc is the default cancel while dictating and does not reach other apps; the
  Flow Bar has stop and cancel controls.
- Errors: notification with *Retry* / *Open History*; audio kept for retry offline.
- Onboarding: sign-in → Microphone + Accessibility (granted steps skipped) → mic test
  (“confirm the bars rise”) → shortcut → languages → practice → data preference.
- Settings separated from the feature sidebar (General / System / Account / Data).
- **SayIt must:** show the outcome — including failure and what to do — inside the HUD
  itself, not in a separate notification.

**Superwhisper** — https://superwhisper.com · https://superwhisper.com/docs
- HUD: Esc or click to cancel; stop button on hover; live words with realtime models.
- Menu bar dot: yellow loading, red recording, blue processing, green done.
- Onboarding asks Microphone (“to record your voice”) then Accessibility (“to paste
  text into other apps”), then language/model/mic.
- **SayIt must:** never signal state by color alone — every state pairs a glyph or
  motion change with a text label (works for color-blind users and VoiceOver).

**VoiceInk** (GPL-3.0) — https://github.com/Beingpax/VoiceInk · https://tryvoiceink.com/docs
- Notch recorder sized to the physical notch; expand with spring(0.42, 0.80), collapse
  critically damped; state cross-fades 0.2s.
- Esc twice within 1.5s cancels, with a one-time hint.
- Onboarding: permissions each with a one-line reason → mic → local model → API key →
  samples → license.
- **SayIt must:** reach a first successful dictation before any optional step (AI
  provider, keys), and cancel with a single Esc while the overlay is visible.

**Aqua Voice** — https://aquavoice.com · https://aquavoice.com/changelog
- Setup verifies mic and shortcut, then walks through a first dictation in another app
  (v0.19.3, 2026-08-25). Floating bar with orb + waveform (v0.20.0).
- Changelog fix: “microphone UI no longer jumps around when recording”.
- **SayIt must:** confirm the first dictation actually produced text (not merely that
  recording started), and keep overlay geometry stable while text streams in.

**Apple Dictation** — https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac
- Listening shown by a pulsing insertion point and a tone; Esc stops; auto-stop after
  30s of silence. No processing state, no preview.
- **SayIt must:** keep the HUD minimal like Apple's, while adding the processing state
  and the transcript preview Apple lacks.

**Apple Live Captions (macOS)** — https://support.apple.com/guide/mac-help/use-live-captions-mchldd11f4fd/mac
- Captions any app's audio on device; a floating window that can be moved and resized,
  hides itself when no audio is detected (“Keep Onscreen” overrides), pauses from the
  window or the menu bar, and switches between Computer Audio and Microphone.
- Settings for font family, size and colors; “Restore Default Position” in the menu.
- Observed from Apple's documentation, not hands-on: the guide doesn't say how it
  handles mixed Chinese and English, or whether words change after they appear.
- **SayIt must:** caption mixed Chinese–English speech accurately (each line is
  re-transcribed by Qwen), and show which words may still change instead of silently
  rewriting text the viewer is reading. Apple switches between Computer Audio and
  Microphone; SayIt captions both at once, marks whose words each line is, and never
  captions the speakers' sound twice.

## Motion (unverified — shot pages blocked automated fetch)

- https://dribbble.com/shots/23223907-Voice-Notification-Dynamic-Island-Style-Animation
  — one Dynamic-Island-style pill morphing for a voice state.
- https://dribbble.com/shots/24825579-Voice-reaction-for-AI-symbol-Design-by-Gleb-Kuznetsov
  — a single orb reacting to voice.

Used as the bar for “one protagonist, weighted easing”. Easing values were not
inspected; re-check in a browser before using them as review evidence.
