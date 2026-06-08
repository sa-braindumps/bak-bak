# Bak-Bak — Architecture

> System design for **v0.1**. This document explains *how the pieces fit and why they are shaped that way*. For exact behavior and edge cases, see [`SPEC.md`](./SPEC.md). For what ships when, see [`docs/ROADMAP.md`](./docs/ROADMAP.md).

The guiding principle: **the differentiator (corrections that persist and compound) rests on a deterministic, file-backed core; everything else is plumbing arranged so that core can be small, testable, and never blocked.**

---

## 1. Component map

A single Swift Package, one binary, two third-party dependencies total (`TOMLKit`, `ArgumentParser`). Everything else is first-party Apple. The binary runs in **app mode** (`NSApplication`) or **CLI mode** (`ArgumentParser` subcommands) depending on how it is invoked.

```
bak-bak/
├── Package.swift                      # SPM; deps: TOMLKit, swift-argument-parser
├── Sources/
│   ├── Pipeline/                      # ── the core loop, UI-free, AX-free, testable
│   │   ├── AudioRecorder.swift        #    AVAudioEngine → in-RAM buffer
│   │   ├── Transcriber.swift          #    URLSession multipart → OpenAI Whisper
│   │   ├── Substitutor.swift          #    deterministic [vocab] replace (the guarantee)
│   │   ├── Injector.swift             #    AXUIElement / CGEvent keys / NSPasteboard
│   │   ├── ProfileStore.swift         #    TOMLKit read/write, comment-preserving
│   │   └── CorrectionGrammar.swift    #    parse "no/correction/actually X is Y"
│   ├── App/                           # ── menu-bar app; owns OS integration + state
│   │   ├── main.swift                 #    mode dispatch (app vs cli)
│   │   ├── HotkeyMonitor.swift        #    CGEvent tap + NSEvent monitor (hold/release)
│   │   ├── StatusItem.swift           #    NSStatusItem, 4 states, tooltips
│   │   ├── CorrectionController.swift #    10s window, grammar match, in-place rewrite
│   │   └── AppCoordinator.swift       #    wires HotkeyMonitor → Pipeline → StatusItem
│   └── CLI/                           # ── the 4 commands; same binary
│       ├── Setup.swift                #    4-action flow (paste→validate→hotkey→a11y)
│       ├── Doctor.swift               #    read-only diagnostic checklist
│       └── Vocab.swift                #    `vocab add`, `vocab list`
└── Tests/
    ├── PipelineTests/                 # unit: Substitutor, CorrectionGrammar, ProfileStore
    └── IntegrationTests/              # stubbed Whisper, Injector, HotkeyMonitor (gated)
```

### What goes where (the rule)

- **`Sources/Pipeline/`** — pure-ish logic for `record → transcribe → substitute → inject`, plus the TOML store and grammar parser. Knows nothing about `NSStatusItem`, the hotkey, or the correction window. Depends only on Foundation/AVFoundation/ApplicationServices + TOMLKit. **This is the part with the most tests and the fewest reasons to change.**
- **`Sources/App/`** — everything that needs OS integration and mutable UI state: the hotkey, the menu bar, and the `CorrectionController` that orchestrates the 10-second window. Depends on `Pipeline`.
- **`Sources/CLI/`** — the four subcommands. Depends on `Pipeline` (it reads/writes the same `ProfileStore`, validates keys via the same `Transcriber` surface, etc.). Depends on `ArgumentParser`.

---

## 2. Data flow — hotkey press to text injection

```
 ┌── user ──┐
 │  holds ⌥ │
 └────┬─────┘
      │ keyDown (modifier-only)
      ▼
 HotkeyMonitor ────────────────▶ StatusItem: recording (red dot, held)
   (CGEvent tap +                       ▲
    NSEvent monitor)                    │ state
      │ start()                         │
      ▼                                 │
 AudioRecorder  ── frames ──▶ [ in-RAM audio buffer ]   (never to disk)
      ▲                                 │
      │ keyUp                           │
 HotkeyMonitor ──── stop() ────────────▶ StatusItem: transcribing (pulse)
      │ flush buffer
      ▼
 Transcriber ── multipart POST ──▶ OpenAI Whisper ──▶ raw transcript
   (URLSession,                                            │
    latency measured)                                      ▼
                                              Substitutor.apply([vocab])
                                                           │  (case-insensitive,
                                                           │   longest-first, on
                                                           │   token boundaries)
                                                           ▼
                                                   corrected text
                                                           │
                                       ┌───────────────────┴───────────────────┐
                                       │ Accessibility granted?                  │
                                       ├── yes ──▶ Injector via AXUIElement       │
                                       └── no  ──▶ Injector via NSPasteboard      │
                                                  + StatusItem: "copied to clip"  │
                                                           │
                                                           ▼
                                              StatusItem: idle (dim mic)
                                                           │
                                                           ▼
                          CorrectionController opens 10s window  ───────────┐
                                                                            │
                          next utterance ──▶ CorrectionGrammar.parse        │
                              │                                             │
            ┌─────────────────┴───────────────────┐                        │
            │ MATCH ("no, X is Y")                 │ NO MATCH               │
            ▼                                      ▼                        │
   ProfileStore.learn(X→Y)              treat as new normal dictation       │
   (+ "# learned <ts>" comment)         (back to top of this flow)          │
            │  ← the durable flywheel write                                 │
            ▼                                                               │
   in-place rewrite:  backspace×N + retype  (N = prior injection length)    │
            │  if N unknown (focus changed) → skip delete, inject only ─────┘
            ▼
        idle
```

The only outbound network call is the Whisper POST. The audio buffer exists only in RAM. The only thing written to disk is `profile.toml` (and only on a learned correction or CLI vocab edit).

---

## 3. State machine

App-level states map 1:1 to the four menu-bar states (see [SPEC §6](./SPEC.md#6-menu-bar-specification)), with the correction window as a sub-state of idle.

```
        ┌─────────────────────────────────────────────────────────────┐
        │                                                               │
        ▼                                                               │
   ┌────────┐  ⌥ down   ┌───────────┐  ⌥ up   ┌──────────────┐         │
   │  IDLE  │──────────▶│ RECORDING │────────▶│ TRANSCRIBING │         │
   └───┬────┘           └─────┬─────┘         └──────┬───────┘         │
       │                      │ tap < 300ms          │                 │
       │                      │ (discard)            │ injected        │
       │                      ▼                      ▼                 │
       │                  ┌────────┐            ┌────────┐  done        │
       │                  │  IDLE  │            │  IDLE  │──────────────┘
       │                  └────────┘            └────┬───┘
       │                                             │ opens
       │   ◀── 5s ──┐                                ▼
       │        ┌────────┐   any failure     ┌──────────────────────┐
       └───────▶│ ERROR  │◀──────────────────│ IDLE: correction      │
                └────────┘  (from any state) │ window (≤ N seconds)   │
                  reason on hover            └───────┬───────────────┘
                                                     │ utterance
                                          ┌──────────┴───────────┐
                                          │ match → learn+rewrite│ no match → RECORDING
                                          └──────────┬───────────┘ (new dictation)
                                                     ▼
                                                   IDLE
```

Notes:
- **RECORDING** is bound to the physical key being held — it cannot be entered or left except by `⌥` down/up.
- **ERROR** is reachable from any state, always carries a reason, always self-clears after 5 s to **IDLE**.
- The **correction window** is a timed sub-state of IDLE; it has no icon of its own (no fifth state) because the on-screen rewrite is the feedback.

---

## 4. Dependency graph

Arrows mean "knows about / imports". The shape enforces that the testable core never depends on UI or OS-event machinery.

```
                    ArgumentParser        TOMLKit
                          │                  │
        ┌─────────────────┘                  │
        ▼                                     ▼
   Sources/CLI ───────────────────────▶ Sources/Pipeline ◀─────────── Sources/App
   (Setup, Doctor, Vocab)                 (AudioRecorder,              (HotkeyMonitor,
        │                                  Transcriber,                 StatusItem,
        │                                  Substitutor,                  CorrectionController,
        │                                  Injector,                     AppCoordinator)
        │                                  ProfileStore,                       │
        │                                  CorrectionGrammar)                  │
        └──────────────── both read/write the same ProfileStore ──────────────┘

   Pipeline depends on: Foundation, AVFoundation, ApplicationServices, TOMLKit
   App      depends on: AppKit, ApplicationServices, Pipeline
   CLI      depends on: ArgumentParser, Pipeline
```

Key constraints:
- **`Pipeline` depends on nothing in `App` or `CLI`.** It is a leaf. This is what makes the substitution guarantee and grammar parser unit-testable without a UI, a mic, or Accessibility.
- **`App` and `CLI` never talk to each other** — they share only the `Pipeline` (notably `ProfileStore`), which is the single source of truth.
- **`CorrectionController` lives in `App`, not `Pipeline`**, because it needs the prior-injection length (UI state) and the timed window. The *parsing* it relies on (`CorrectionGrammar`) is in `Pipeline` so it can be tested in isolation.

---

## 5. Key design decisions (and why)

Each decision was a debate finding. They are recorded here so a future contributor changing one does it on purpose, knowing the cost.

### 5.1 Deterministic string replace over Whisper prompt-priming
Whisper's `initial_prompt` is best-effort and version-fragile — the same prompt yields different output across model versions, and a term is never *guaranteed* corrected. The entire product promise is "your correction sticks." A guarantee cannot be built on a hint to a model. So the substitution layer is a deterministic, case-insensitive string replace from a file the user owns. Prompt-priming returns in **v0.2 as an optimization layer on top of** substitution — never as a replacement.

### 5.2 Backspace-delete + retype over AXValue replacement
The in-place correction rewrite synthesizes backspaces (`CGEvent`) then types the corrected text, instead of setting `AXValue` directly. `AXValue` behaves differently across apps and produces artifacts in editors with vim mode, autocomplete, or custom text engines (reordered/duplicated text, triggered completions). Backspace+retype is what a human does and is universally compatible. The cost — needing to know the prior injection length — is paid by the [focus-changed safety rule](#56-the-focus-changed-safety-rule).

### 5.3 The flywheel ships in v0.1, not v0.2
The single differentiator is "corrections persist and compound." Deferring it would ship a generic dictation app (of which good ones already exist) with a promise of the real product later. The debate consensus was explicit: the flywheel must be visible within the first 60 seconds of use, so the substitution layer **and** voice correction both ship in v0.1.

### 5.4 Voice correction over `⌘Z` auto-capture
An earlier design captured corrections by watching for `⌘Z` + retype. Voice correction supersedes it: it is a single modality (you were already talking), it captures the *intended* term explicitly ("...is kubectl") rather than inferring it, and it does not fight the host app's own undo stack. `⌘Z` capture is cut.

### 5.5 No confirmation loop on corrections
A learned correction is written immediately on grammar match — no interactive y/n. A confirmation prompt would (a) break the "four actions, just talk" ethos, and (b) make every dictation feel interrogated. The safety net is that corrections are plain text in `profile.toml` and trivially editable/removable.

### 5.6 The focus-changed safety rule
If the prior injection length is unknown (commonly because focus changed between dictation and correction), the rewrite **skips the delete step** and injects only the corrected text. Blind backspacing could eat text the user never dictated. Principle: losing the in-place rewrite is acceptable; eating the user's other text is not — and the `[vocab]` write (the flywheel) happens regardless.

### 5.7 TOMLKit because comments are load-bearing
Learned corrections are stored as `"X" = "Y"` plus a `# learned <timestamp>` comment, and `bak-bak doctor` reads those comments back to show recent corrections. There is no separate `corrections.log`. A TOML writer that drops comments would destroy history on every edit. Hand-rolling a comment-preserving writer is not worth it, so TOMLKit (comment-preserving) is a hard dependency.

### 5.8 Audio in RAM only (AVAudioEngine)
`AVAudioEngine` streams frames into a RAM buffer that is flushed on key release and discarded after transcription (and on every error path). There is no code path that writes audio to disk. This is what makes the "audio is never written to disk" privacy promise structural rather than a claim.

### 5.9 One network surface (URLSession, no SDK)
A single multipart `URLSession` POST to the Whisper endpoint is the only outbound call. No vendor SDK. This keeps the privacy story auditable and makes latency reporting in `doctor` a one-liner (measure the round-trip of the only call there is).

### 5.10 Four menu-bar states, no "learned" state
idle / recording / transcribing / error — and no fifth "learned" state. When a correction is learned, the on-screen text rewrite *is* the feedback; a fifth icon would be redundant. `NSStatusItem` + template images + tooltips; no animation framework (the pulse is alternating images).

### 5.11 Single binary, app + CLI
The same binary serves the menu-bar app and the four CLI commands (`ArgumentParser` for mode dispatch and free help/validation). One thing to build, sign, distribute, and reason about.

### 5.12 Native Swift + AppKit, macOS 13+, no Catalyst/Electron
The product *is* deep OS integration — global hotkey, in-RAM capture, AX injection, menu bar. Those are first-class on native AppKit and awkward or impossible elsewhere. macOS 13+ is the floor.

---

## 6. Extension points

The v0.1 structure is arranged so v0.2/v0.3 features slot in without rewriting the core loop. Each extension point is a seam that already exists.

### 6.1 Whisper prompt-priming (v0.2) — a stage *before* `Transcriber`, not inside `Substitutor`
The `[vocab]` map can be rendered into an `initial_prompt` and attached to the Whisper request. This is purely additive: it sits in `Transcriber` as an optional request parameter, and `Substitutor` still runs afterward as the guarantee. If priming helps, fewer corrections are needed; if it regresses, substitution still catches everything. No existing code is rewritten.

### 6.2 Per-app re-injection hardening (v0.2) — strategy behind `Injector` / `CorrectionController`
The rewrite mechanics (§5.2) can grow per-app strategies (e.g. known-quirky editors) behind the existing `Injector` interface and the length-tracking in `CorrectionController`. The §5.6 safety rule is the default fallback for any app without a tuned strategy.

### 6.3 Vocab hit-counts (v0.2) — metadata in `ProfileStore`, surfaced by `doctor`
Counting how often each entry fires is an annotation on `[vocab]` entries (or a sibling comment) written by `Substitutor` and read by `Doctor`. It was cut from v0.1 as an unactionable number; the seam is the same `ProfileStore` read/write path already used for learned-correction comments.

### 6.4 LLM cleanup with style seed (v0.3) — a stage *after* `Substitutor`, *before* `Injector`
`[style].seed` already exists in `profile.toml` (parsed, ignored in v0.1). A `Cleanup` stage in `Pipeline` reads the seed into a system prompt and post-processes the substituted text via a second, optional API key. It is an opt-in stage inserted in the pipeline; substitution still runs first, so the guarantee is preserved even with cleanup on.

### 6.5 New correction grammars — add a pattern in `CorrectionGrammar`
The three patterns ("no/correction/actually X is Y") live in `Sources/Pipeline/CorrectionGrammar.swift` as a list of pattern matchers. Adding one is adding a matcher + tests, with no change to `CorrectionController`. See [CONTRIBUTING §7](./docs/CONTRIBUTING.md#7-how-voice-correction-grammar-patterns-are-parsed).

### 6.6 Backlog seams
- **Local whisper.cpp mode** — `Transcriber` is the only thing that knows the transcript came from the network; it can become a protocol with an OpenAI implementation and a local implementation. The rest of the pipeline is source-agnostic.
- **Per-app style profiles** — a keyed extension of `[style]` resolved by frontmost-app bundle id, consumed by the v0.3 `Cleanup` stage.
- **Non-English vocab packs** — additive `[vocab]` content; the `Substitutor` is already language-agnostic (it is string replacement).
