# SayIt Design Spec

Status: v1, 2026-10-12. This is the design spec required by the design SOP
(`sopd/docs/RULES.md` §4 and `sop-studio/docs/VISUAL-DESIGN-ACCEPTANCE.md`).
Code is the source of truth for values: `Sources/SayIt/Theme/`.

## 1. Audience and use

SayIt is for people who write all day on a Mac — engineers, writers, support and
operations staff — often switching between Chinese and English in one sentence.
They use it in short bursts: press a shortcut, speak for 5–60 seconds, and expect
text to appear in whatever app has focus. The app is in the menu bar; the main
window is opened rarely, to set up, tune or review.

Two surfaces follow from that:

- **The overlay (HUD)** is used hundreds of times a day. It must be glanceable,
  quiet, and always say what is happening: listening, working, done, or failed.
- **The main window** is used occasionally. It must make setup obvious, keep
  settings findable, and show what SayIt has written.

## 2. Core concept: voice becomes writing

Every touchpoint shows the same transformation — sound turning into words.

| Touchpoint | How the concept shows |
| --- | --- |
| Type | Interface chrome is set in SF Pro. Words the user has spoken (transcripts, previews, history) are set in **New York**, the system serif, so spoken output reads as *written*. |
| Overlay | A live level meter while listening; when work finishes the meter resolves into a single mark (✓ inserted, ! failed) before leaving. |
| Menu bar | A static waveform frame while recording and a writing frame while working (`menubar_wave_*`, `menubar_write_*`). It does not loop: while the overlay is up, the overlay's meter is the one moving element. |
| Home | Hero line in New York: “Say it, and it's written.” The test area shows the transcript in serif as it arrives. |
| Color | One accent (user-selectable) marks the path forward; status colors have fixed meanings. Everything else is neutral, so the words are the loudest thing on screen. |

## 3. Style direction

**Quiet instrument.** Native macOS structure (sidebar, grouped cards, standard
controls) with calm, layered neutrals, hairline edges instead of heavy shadows,
generous spacing, and an editorial serif for spoken words. No decorative gradients,
glows or glass on scrolling content.

Why it fits: dictation is a tool people keep running all day; the UI should feel
precise and calm and get out of the way. The serif/sans split carries the concept
without adding ornament.

## 4. Tokens

Defined in `Theme/AppTheme.swift`, `Typography.swift`, `Motion.swift`. Never use
numeric literals for color, font size, spacing or radius in views.

- **Color.** Palettes resolve per appearance (light/dark) and contrast setting.
  Surface ladder (dark): window 0.07 · content 0.075 · surface 0.10 · raised 0.13;
  sunken 0.055 for wells. Light: window 0.955 · surface 1.0 · sunken 0.94.
  Text tokens meet 4.5:1 on every surface. `accentForeground` is the accent adjusted
  until it reaches 4.5:1 as text; `onAccent` picks near-black or white for text on an
  accent fill. Status colors (`success`, `warning`, `error`, `info`, `recording`) are
  fixed and never follow the accent.
- **Type.** `AppFont`: display (26 serif) · pageTitle (title2 semibold) · sectionTitle
  (headline) · rowTitle · body · callout · caption (11pt, smallest information text) ·
  micro (10pt, badges/key caps only) · metric (28 rounded, monospaced digits) · mono ·
  transcript (serif). Overlay scale: `AppFont.Overlay` (min 11pt).
- **Spacing.** `Space`: 2 · 4 · 8 · 12 · 16 · 20 · 28 · 40. Page padding 28; gap
  between cards 20; inside cards 16; between rows 12.
- **Radius.** `Radius`: 4 · 6 · 8 · 12 · 16 · pill. Controls 6–8, cards 12, prominent
  tray 16 holding a 12 core with a 4pt inset (concentric).
- **Elevation.** Dark mode: hairline + 1pt top highlight; shadows only for floating
  layers. Light mode: hairline + soft diffuse shadow (≤ 10% black).

## 5. Components

- **Buttons** (`.sayItPrimary / .sayItSecondary / .sayItQuiet / .sayItDestructive`,
  sizes small/regular/large). One primary per view. Every style shows disabled
  (45% opacity, no hover) and pressed states. Icon-only actions use `IconButton`,
  which requires a label (VoiceOver + tooltip).
- **Cards** (`ThemedCard`): `standard` for groups, `prominent` for the single focal
  card on a page (nested tray + core), `subtle` for an inset group.
- **Rows**: title (rowTitle) + one line of secondary text, control trailing. Toggles
  and pickers always carry a real label (use `.labelsHidden()` only when a visible
  `Text` is attached via `accessibilityLabel`/`LabeledContent`).
- **Status**: glyph + text, never color alone. Badges use `palette.subtle(color)`.
- **Empty states**: what this place will contain, why it is empty, and the one action
  that fills it.
- **Destructive actions**: confirmation dialog naming what will be lost
  (“Delete Qwen3-ASR 1.7B? This removes 2.47 GB from disk.”), destructive button role.

## 6. Information architecture

Sidebar, in sections (Title Case, outline SF Symbols at regular weight):

- **Home** — setup checklist until setup is complete, then status (engine, shortcut,
  permissions), the test area and recent dictations. Always first; the default page.
- **Activity** — History, Stats
- **Tools** — Command Mode, File Transcription
- **Settings** — General, Voice Engine, Dictionary, AI Enhancement
- **Help & Feedback**

Selecting a sidebar item never changes global behaviour (shortcuts, overlay mode).

## 7. Motion

Benchmark: Dribbble Popular-tier motion — purposeful, weighted, choreographed.

- One protagonist at a time. While listening only the level meter moves.
- Entrances decelerate (`Motion.enter`, expo-out 0.28s); exits accelerate
  (`Motion.exit`, 0.16s); on-screen state changes use `Motion.state` (spring 0.34/0.86);
  hover/press `Motion.snappy`; one celebratory beat `Motion.emphasis`.
- Stagger lists by `Motion.stagger` (40 ms), max 6 items.
- Transitions connect states: the overlay meter resolves into the outcome mark; text
  changes use content transitions, not fades of the whole container.
- Ambient loops (working shimmer) use `Motion.ambient`, period 1.6s, and run only while
  work is in progress.
- **Reduce Motion**: spatial motion becomes a 0.16s cross-fade, ambient loops stop, the
  level meter changes opacity instead of height. Use `withMotion`, `.motion(_:value:)`,
  `.motionTransition()`, `.ambientPulse()` — never raw `withAnimation`/`repeatForever`.
- Animate transform and opacity only; no per-frame layout (`frame(height:)`) animation.

## 8. Recording overlay

Single state model `OverlayPhase` (starting · listening · transcribing · refining ·
done(outcome) · failed(reason) · cancelled), rendered identically in the notch and
bottom styles.

- Layout: mode glyph + status text (leading), level meter or progress (center),
  shortcut hint / close button (trailing); transcript preview below in serif.
- Working states keep the transcript visible at reduced emphasis and show the status
  on its own line.
- Terminal states stay for `Motion.outcomeDwell` (1.1s) so they can be read, then exit.
  If the overlay had already left, it returns briefly for anything the user must know
  (failed, no speech, original text inserted, copied instead of typed) — not for a plain
  successful insert.
- Cancelling while transcribing or enhancing discards the result: nothing is typed,
  copied or saved (`NotchContentState.cancellationCount`).
- The overlay appears on the screen of the app that will receive the text, falling back
  to the screen under the pointer.
- Mode glyphs: Dictate `mic`, Edit `pencil.line`, Command `terminal`; the glyph
  always pairs with the mode name, never color alone.
- Esc cancels from any phase while the overlay is visible; Esc is never consumed when
  the overlay is hidden. The close button does the same.
- Every phase change is announced to VoiceOver (`OverlayPhase.announce()`).
- The overlay is always dark (`sayItOverlayTheme()`): it sits beside the hardware notch
  and over arbitrary content. Mode colors: Dictate neutral white, Edit blue, Command
  amber. Red is reserved for recording/error.

## 9. Copy

House style for every user-facing string. Copy errors are release blockers.

- **Glossary.** Dictate Mode · Edit Mode · Command Mode · AI Enhancement (the feature;
  history badge “Enhanced”) · Voice Engine · speech model · Dictionary · keyboard
  shortcut (“shortcut” in short labels; never “hotkey”) · Settings (never
  “Preferences”) · File Transcription · Home.
- **Capitalization.** Title Case for buttons, menu items, page/section titles, sidebar
  items. Sentence case for toggle/checkbox labels, descriptions, help and messages.
- **Punctuation.** Ellipsis “…” (one character) for in-progress states and items that
  open a dialog. Em dash “—” without spaces. En dash for ranges (“65–75 WPM”). Curly
  quotes “ ” ‘ ’.
- **Numbers.** Always agree: `CopyFormat.count(n, "word")` → “1 word”, “2 words”.
- **Keys.** Symbols in shortcuts (⌘ ⌥ ⇧ ⌃ ↩ ⎋); “Esc” in prose; “⌘-Tab”.
- **Voice.** Plain, direct, second person. Say what happened and what to do next.
  Never show internal notes, build details, contributor names or debugging text.

## 10. Accessibility

- Contrast: text ≥ 4.5:1 (enforced by palette); no information text below 11pt.
- Every control has a label; icon-only controls use `IconButton`. Selection uses the
  `.isSelected` trait, completion is an accessibility value, not `.disabled`.
- All interactive elements are Buttons or controls (no `onTapGesture` on rows) and
  reachable with Full Keyboard Access; lists support arrow keys, ⌫ and ⌘C where they
  hold items.
- Respect Reduce Motion, Increase Contrast (palette switches) and Reduce Transparency
  (materials fall back to solid surfaces).

## 11. Window sizes

The SOP's mobile/portrait requirement maps to compact window sizes on macOS: the
main window works at its minimum size (800 × 560) with the sidebar visible; cards
reflow to one column under 640pt of content width; the overlay has small, medium
and large sizes and must keep status text on one line at the small size.

## 12. Skill adaptation (`high-end-visual-design`)

The skill targets web (Tailwind). Rules applied, adapted, or replaced:

| Skill rule | SayIt |
| --- | --- |
| Banned fonts (Inter, Helvetica…) | Applied: SF Pro + New York only. |
| Ultra-light icon set | Adapted: SF Symbols, outline variants at regular weight; no mixed filled/outline sets. |
| No 1px gray borders, no harsh shadows | Applied: semantic hairlines at 9–10% and ≤ 24% diffuse shadows; dark mode uses top highlights. |
| Double-bezel containers | Applied to `ThemedCard(.prominent)` only (one focal card per page); everywhere else it would fight native density. |
| Pill buttons with nested icon circle | Replaced: macOS rounded-rect controls (radius 6–12) match system controls and keyboard focus rings. |
| Floating glass nav / hamburger | Not applicable: native sidebar. |
| py-24…py-40 macro whitespace | Adapted: 28pt page padding, 20pt card gaps — settings density is a task requirement. |
| Custom cubic-bezier motion, no linear/ease-in-out | Applied via `Motion` tokens. |
| Scroll-reveal entrances | Not applied to settings pages (would slow reading); used for overlay entrance and Home checklist stagger only. |
| Blur only on fixed layers | Applied: materials only on window chrome and overlay. |
| Mobile collapse < 768px | Replaced by §11 window-size rules. |

## 13. References

Observation date 2026-10-12. Wispr Flow, Superwhisper, VoiceInk, Aqua Voice and Apple Dictation, each with the practice SayIt must beat: see `REFERENCES.md`.

## 14. Evidence

- Static: `Tests/SayItUISnapshots` renders each screen and state in light and dark.
  Run with `TEST_RUNNER_SAYIT_SNAPSHOT_DIR=/path xcodebuild test -scheme SayIt
  -only-testing:SayItDictationIntegrationTests` (see `SnapshotRenderer.swift`).
- Motion: requires screen recording of the overlay phases; until recorded, the motion
  verdict stays “待验证”.
