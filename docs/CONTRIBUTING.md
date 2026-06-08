# Contributing to Bak-Bak

> *बक-बक* — Hindi for chattering. Thanks for helping build it.

Before you write code, read [`SPEC.md`](../SPEC.md) (the behavior contract) and [`ARCHITECTURE.md`](../ARCHITECTURE.md) (how the pieces fit and *why*). This guide covers building, the project layout, where to start, code style, testing requirements, and how the voice-correction grammar is parsed so you can add patterns.

The product is **one bet**: corrections that persist and compound. The single rule that governs every contribution: **never weaken the guarantee** that a taught term (`profile.toml [vocab]`) is corrected on the next dictation, and **never let a bad config, a denied permission, or a failed rewrite block the user from dictating or cost them a learned correction.**

---

## 1. How to build locally

**Requirements**
- macOS 13+ (the product *is* deep OS integration; there is no cross-platform build).
- A recent Xcode / Swift toolchain (Swift Package Manager).
- An OpenAI API key for manual end-to-end testing (not needed for unit tests).

**Build and run**
```bash
git clone <your-fork-url> bak-bak
cd bak-bak

# Build everything (single binary: app + CLI).
swift build

# Run unit tests (no OS permissions, no network — these must pass before any PR).
swift test

# Run the CLI surface during development.
swift run bak-bak doctor
swift run bak-bak vocab list
```

**Running the menu-bar app from source** requires the usual macOS permissions:
- **Microphone** — to capture audio.
- **Accessibility** — to inject text at the cursor (without it, text goes to the clipboard, which is a valid path to test too).
- **Input Monitoring / event tap** — for the global hold-`⌥` hotkey.

Grant these in *System Settings → Privacy & Security*. The first launch of an unsigned build may show *"can't be opened"* — right-click the app → **Open**. `swift run bak-bak doctor` tells you exactly which permissions are missing.

**Dependencies** (two, both via SPM, declared in `Package.swift`):
- [`TOMLKit`](https://github.com/LebJe/TOMLKit) — **must be comment-preserving** (learned-correction timestamp comments are read back by `doctor`).
- [`swift-argument-parser`](https://github.com/apple/swift-argument-parser) — the CLI.

Everything else is first-party Apple. Do not add a third dependency without raising it in an issue first — keeping the dependency surface tiny is a design goal.

---

## 2. Project structure walkthrough

```
bak-bak/
├── Package.swift            SPM manifest. Two deps: TOMLKit, swift-argument-parser.
├── SPEC.md                  Behavior contract (read first).
├── ARCHITECTURE.md          How it fits together and why (read second).
├── VISION.md                The pitch / positioning.
├── docs/
│   ├── ROADMAP.md           What ships in v0.1 / v0.1.1 / v0.2 / v0.3 / backlog.
│   └── CONTRIBUTING.md       This file.
├── Sources/
│   ├── Pipeline/            The testable core. UI-free, AX-free. Most tests live here.
│   │   ├── AudioRecorder.swift     AVAudioEngine → in-RAM buffer. NEVER writes to disk.
│   │   ├── Transcriber.swift       URLSession multipart → OpenAI Whisper. Measures latency.
│   │   ├── Substitutor.swift       Deterministic [vocab] replace. THE GUARANTEE — touch carefully.
│   │   ├── Injector.swift          AXUIElement / CGEvent backspace+retype / NSPasteboard fallback.
│   │   ├── ProfileStore.swift      TOMLKit read/write, comment-preserving. Learned-correction comments.
│   │   └── CorrectionGrammar.swift Parses "no/correction/actually X is Y". Add patterns here.
│   ├── App/                 Menu-bar app: OS integration + mutable UI state. Depends on Pipeline.
│   │   ├── main.swift              Mode dispatch: app vs CLI.
│   │   ├── HotkeyMonitor.swift     CGEvent tap + NSEvent monitor (hold/release ⌥).
│   │   ├── StatusItem.swift        NSStatusItem, exactly 4 states, hover tooltips.
│   │   ├── CorrectionController.swift  10s window, grammar match, in-place rewrite, length tracking.
│   │   └── AppCoordinator.swift    Wires HotkeyMonitor → Pipeline → StatusItem.
│   └── CLI/                 The 4 commands. Same binary. Depends on Pipeline + ArgumentParser.
│       ├── Setup.swift            4-action flow: paste → validate → hotkey → accessibility.
│       ├── Doctor.swift           Read-only diagnostic checklist.
│       └── Vocab.swift            `vocab add`, `vocab list`.
└── Tests/
    ├── PipelineTests/        Unit tests for Substitutor, CorrectionGrammar, ProfileStore, length math.
    └── IntegrationTests/     Stubbed Whisper, Injector, HotkeyMonitor (require permissions; gated).
```

**The directory rule.** If your code reads/writes the profile, talks to Whisper, substitutes vocab, injects text, or parses a correction grammar, it belongs in **`Pipeline/`** and must be testable without a UI or OS permissions. If it needs the menu bar, the live hotkey, or the timed correction window, it belongs in **`App/`**. If it is one of the four commands, it belongs in **`CLI/`**. `App` and `CLI` may depend on `Pipeline`; `Pipeline` may depend on neither.

---

## 3. Where to start (good first issues)

Ordered roughly easiest → meatiest. Look for the `good first issue` label on GitHub; these are the kinds of things it marks:

- **New correction grammar pattern** — add a phrasing (e.g. "I meant Y" / "spell it Y") in `CorrectionGrammar.swift` with tests. Self-contained; see [§7](#7-how-voice-correction-grammar-patterns-are-parsed).
- **Substitutor edge-case tests** — strengthen token-boundary, capitalization-preservation, and longest-key-first coverage. High value, no OS dependencies.
- **`doctor` output polish** — alignment, clearer reasons, better "last 5 corrections" formatting.
- **`vocab list` formatting** — column alignment with wide/Unicode entries.
- **Setup copy** — clearer prompts and the unsigned-build / Accessibility instructions.
- **ProfileStore round-trip tests** — prove comments survive every write path.
- **Per-app injection strategy** (bigger, v0.2-flavored) — improve in-place rewrite fidelity behind the `Injector` interface for a specific editor.

If you want to attempt something larger, open an issue first so we can confirm it fits the roadmap and does not collide with the v0.1 cuts in [ROADMAP](./ROADMAP.md).

---

## 4. Code style

- **Swift API Design Guidelines.** Clear names over clever ones. Prefer value types and `async/await` (the pipeline is async end to end).
- **Keep `Pipeline/` pure-ish.** No `import AppKit` in `Pipeline`. No global mutable state. Dependencies (the network call, the clock, the keystroke synthesizer) should be injectable so they can be stubbed in tests.
- **No new dependencies** without an issue. Two is the budget.
- **Named constants, not magic numbers.** `correction_window_secs` is configurable in `profile.toml`; the ~300 ms tap-too-short threshold, the 30 s request timeout, and the 5 s error-state duration are named constants — keep it that way.
- **Errors carry user-facing reasons.** Every failure maps to one of the reasons in [SPEC §8](../SPEC.md#8-error-handling). If you add an error, add its reason string and its menu-bar/CLI surfacing.
- **Comments explain *why*, not *what*.** And remember: in `profile.toml`, comments are *data* (`doctor` reads them) — never strip them on a write.
- **Format before committing** (`swift format` / the project's configured formatter). CI will check.

---

## 5. Privacy invariants you must not break

These are not style preferences — a PR that violates them will be rejected:

1. **Audio never touches disk.** `AudioRecorder` streams to a RAM buffer, flushed on release, discarded after transcription and on *every* error path (including "recording too long"). There must be no code path that writes audio to a file.
2. **One network surface.** The only outbound call is the Whisper POST in `Transcriber`. Do not add telemetry, analytics, crash reporters, or any other network call.
3. **No hidden state.** Everything Bak-Bak knows lives in `profile.toml` and is printable by `bak-bak vocab list`. Do not introduce a sidecar database, a cloud sync, or a separate `corrections.log` (correction history lives in TOML comments).

---

## 6. Testing requirements before PR

**Required for every PR:**
- `swift test` (unit tests) passes locally and in CI. Unit tests run with **no OS permissions and no network**.
- New behavior in `Pipeline/` ships with unit tests. The highest-value targets:
  - **Substitutor** — case-insensitivity, verbatim value insertion, token boundaries (`nicks` must not hit `picnicks`), multi-word keys, longest-key-first ordering, empty/missing/malformed config falling back to passing the raw transcript through (dictation is never blocked).
  - **CorrectionGrammar** — every pattern, case-insensitive keyword/connective, filler/punctuation stripping, correct X/Y capture, and non-matching utterances classified as normal dictation.
  - **ProfileStore** — round-trip read/write **preserving comments**; a `# learned <ISO-8601-Z>` comment is written on a learned correction; `doctor`'s "last 5 corrections" parse correctly from comments; a malformed file is handled without throwing into the dictation path.
  - **Length-tracking for rewrite** — correct backspace count from a known prior injection; **unknown length ⇒ skip-delete** (the focus-changed safety rule), never a guessed count.

**Integration tests** (in `IntegrationTests/`) require permissions or a stub server and are **gated** — run them locally for anything touching `Transcriber`, `Injector`, or `HotkeyMonitor`:
- `Transcriber` against a **stubbed Whisper endpoint**: multipart body shape, latency capture, and 401/429/5xx/timeout → correct error reasons. **Never call the real OpenAI API in tests.**
- `Injector`: AX insertion into a known field; clipboard fallback when Accessibility is denied, including the explicit "copied to clipboard" message.
- `HotkeyMonitor`: modifier-only press/release detected; `⌥`+other-key passes through; tap-too-short discarded.

**Manual acceptance for the differentiator.** If you touch the correction loop, run the 90-second demo by hand and confirm it: wrong text → "no, cube cuttle is kubectl" → in-place rewrite → say "cube cuttle" again → silent auto-correct → `bak-bak vocab list` shows `cube cuttle = kubectl`. This is the acceptance test for the whole product.

In your PR description, state what you tested and how, and call out anything you could only verify manually (e.g. per-app rewrite fidelity — the documented beta surface).

---

## 7. How voice-correction grammar patterns are parsed

This is the most common "good first issue," so it gets its own section.

### 7.1 Where it lives
All parsing is in **`Sources/Pipeline/CorrectionGrammar.swift`**. It is in `Pipeline/` (not `App/`) so it can be unit-tested without the menu bar or the timed window. The runtime orchestration — opening the 10-second window and performing the rewrite — lives in `App/CorrectionController.swift` and calls into the grammar. **You should not need to touch `CorrectionController` to add a pattern.**

### 7.2 The three v0.1 patterns
Each pattern recognizes a *leading keyword*, the *connective* `is`, and captures `X` (the misheard term) and `Y` (the intended term):

| Pattern | Example | X | Y |
|---------|---------|---|---|
| `no, X is Y` | "no, cube cuttle is kubectl" | `cube cuttle` | `kubectl` |
| `correction: X is Y` | "correction cube cuttle is kubectl" | `cube cuttle` | `kubectl` |
| `actually X is Y` | "actually nicks is Nginx" | `nicks` | `Nginx` |

### 7.3 The parsing model
`CorrectionGrammar` is a **list of pattern matchers**, each of which:
1. Tests whether the utterance begins with the pattern's **leading keyword(s)** ("no", "correction", "actually"), case-insensitively, stripping trailing filler punctuation (`,` / `:`).
2. Splits the remainder on the connective ` is ` (case-insensitive).
3. Captures everything before ` is ` as **X** and everything after as **Y**.
4. Returns a `Correction(heard: X, intended: Y)` on success, or `nil` if the utterance does not fit.

The parser tries each matcher in turn. The **first match wins**. If **no** matcher returns a result, the parser returns `nil`, and the caller (`CorrectionController`) treats the utterance as a normal new dictation — there is **no confirmation prompt**.

### 7.4 Adding a new pattern
1. Add a matcher to the pattern list in `CorrectionGrammar.swift` (e.g. an "I meant Y" pattern that reuses the *last* dictation as X).
2. Keep matching case-insensitive on keyword and connective; strip leading filler.
3. Make sure your matcher returns `nil` cleanly for utterances it does not own, so it never swallows a normal dictation.
4. Add unit tests in `PipelineTests/` covering: the happy path, capitalization variants, filler/punctuation, a near-miss that must *not* match, and confirmation that a plain dictation still returns `nil`.
5. Update the pattern table in [SPEC §7.2](../SPEC.md#72-grammar-patterns) and in §7.2 above.

### 7.5 What the match does next (so you understand the blast radius)
On a successful parse, `CorrectionController`:
1. **Writes `"X" = "Y"` to `[vocab]` with a `# learned <timestamp>` comment** — the durable flywheel write (always reliable; this is what makes the *next* dictation correct).
2. **Rewrites the on-screen text in place** via backspace-delete + retype (the beta part). If the prior-injection length is unknown (focus changed), it **skips the delete and injects only** the correction — it must never blindly backspace and eat surrounding text.

So a grammar change only affects *what gets captured as X and Y*. The durable learning and the safety rules around the rewrite are unchanged — which is exactly why grammar patterns are a safe place to start.

---

## 8. Opening a PR

- Branch off `main`; keep PRs focused (one feature/fix).
- Reference the issue it addresses.
- Confirm `swift test` passes and state what you tested manually.
- Confirm you did not break a privacy invariant (§5) or the substitution guarantee.
- Be ready to explain *why* — every decision in this project has a reason recorded in `ARCHITECTURE.md`, and changes to those decisions should be intentional.

Welcome aboard. बक-बक.
