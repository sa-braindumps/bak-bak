# Bak-Bak — Roadmap

> The one bet: **your corrections should persist and compound.** Every milestone is judged by how directly it serves that flywheel. This roadmap supersedes the milestone sketch in the top-level `VISION.md`: the flywheel ships in **v0.1**, not later — that was the decisive debate finding.

For *what each feature does*, see [`SPEC.md`](../SPEC.md). For *how features slot in without rewrites*, see the extension points in [`ARCHITECTURE.md`](../ARCHITECTURE.md#6-extension-points).

Each milestone below lists: **What ships**, **What it enables**, and **What success looks like**.

---

## v0.1 — the loop *and* the flywheel

The core dictation loop, the deterministic substitution layer, and voice correction (beta) — all in the first release. Shipping the loop without the flywheel would just be another generic dictation app; the flywheel must be visible within the first 60 seconds of use.

**What ships**
- Hold `⌥` to record (audio in memory only, **never written to disk**), release to transcribe.
- OpenAI Whisper API, **one key only**, via a single `URLSession` multipart POST (no SDK).
- Text injection at the cursor via `AXUIElement`; **clipboard fallback** when Accessibility is denied (menu bar says **"copied to clipboard"** explicitly).
- **Deterministic, case-insensitive string replace** from `profile.toml [vocab]`, applied before every injection — the guarantee the flywheel is built on.
- **Voice correction (headline, shipped as documented beta)**: a 10-second window after each injection; three grammar patterns ("no, X is Y" / "correction: X is Y" / "actually X is Y"); on match, write `X = Y` to `[vocab]` with a timestamp comment and rewrite the on-screen text via **backspace-delete + retype** (not AXValue). If prior-injection length is unknown (focus changed), skip the delete and inject only — never eat surrounding text. No match = a normal new dictation, no confirmation loop.
- **Menu bar with exactly 4 states**: idle (dim mic) / recording (red dot, lit while key held) / transcribing (pulse during the API round-trip) / error (red ✗ for 5 s, reason on hover).
- **`bak-bak setup`** — exactly 4 actions: paste key → live validate → confirm hotkey → grant Accessibility (poll until detected). Stops on key failure.
- **`bak-bak doctor`** — mic access, Accessibility, key validity, hotkey registration, last transcription latency (ms), vocab entry count, last 5 corrections (from timestamp comments).
- **`bak-bak vocab add "heard" "intended"`** and **`bak-bak vocab list`**.
- `correction_window_secs` as a named, configurable constant in `profile.toml`.
- **Unsigned `.dmg` on GitHub Releases**, with the right-click → Open workaround documented in the README and printed by `setup`.

**What it enables**
- A developer with a thick accent can teach Bak-Bak a term once (by voice) and have it corrected forever, with zero ML and zero hidden state — the vocabulary is a plain-text file they own, diff, and version.
- The complete 90-second demo: wrong text → "no, cube cuttle is kubectl" → in-place rewrite → say it again → silent auto-correct → `bak-bak vocab list` proves it.

**What success looks like**
- The 90-second demo runs end to end and is the thing people share.
- A new user reaches a first successful auto-corrected term within ~60 seconds of `setup`.
- `bak-bak doctor` makes every "it didn't work" report self-diagnosable.
- The repo earns stars on the strength of the flywheel, not on feature breadth.

**Explicitly cut from v0.1** (and why):
- *Whisper prompt-priming* → v0.2 (unreliable; not worth the debugging surface before the deterministic layer is proven).
- *LLM cleanup / second API key* → v0.3.
- *AXValue in-place rewrite* → replaced by backspace+retype (universally compatible).
- *Menu bar "learned" 5th state* → the on-screen text rewrite IS the feedback.
- *Separate `corrections.log`* → folded into `profile.toml` timestamp comments.
- *Interactive y/n confirmation for corrections* → would break the 4-action setup promise.
- *Baked-in starter vocabulary* → commented example in `profile.toml` + README copy-paste.
- *`⌘Z` auto-capture* → voice correction supersedes it.
- *Vocab hit-counts* → unactionable number (revisited in v0.2).
- *Per-app style profiles, local whisper.cpp, non-English packs* → backlog.
- *Notarization* → v0.1.1 (a signing-cert chore, not a code feature).

---

## v0.1.1 — distribution polish

No new product behavior — just making install painless.

**What ships**
- **Notarized build** (removes the Gatekeeper right-click → Open dance).
- **Homebrew tap** (`brew install bak-bak`).

**What it enables**
- One-command install with no scary "can't be opened" dialog — lowers the barrier for non-technical word-of-mouth installs.

**What success looks like**
- `brew install` works on a clean machine; first launch has no Gatekeeper friction; `doctor` is green out of the box.

---

## v0.2 — the optimization layer

Make the already-reliable flywheel *need fewer corrections*, and harden the rewrite.

**What ships**
- **Whisper prompt-priming as an optimization layer on top of substitution.** The `[vocab]` map is rendered into Whisper's `initial_prompt` so the model mishears taught terms less often. Substitution still runs afterward as the guarantee — priming only reduces how often it has to fire. (Slots into `Transcriber` as an optional request parameter; no rewrite. See [ARCHITECTURE §6.1](../ARCHITECTURE.md#61-whisper-prompt-priming-v02--a-stage-before-transcriber-not-inside-substitutor).)
- **Per-app re-injection hardening.** Per-app strategies behind the `Injector` interface for known-quirky editors, improving in-place rewrite fidelity (the documented-beta surface from v0.1). The focus-changed safety rule remains the default fallback.
- **Vocab hit-counts.** Now that priming and per-app behavior exist, hit-counts become actionable (which terms to prime, which to prune). Surfaced via `doctor`.

**What it enables**
- Fewer corrections needed over time for heavy users with lots of jargon.
- More reliable in-place rewrites in popular dev editors.
- Visibility into which vocabulary actually earns its keep.

**What success looks like**
- Measurable drop in correction frequency for a fixed vocabulary versus v0.1.
- In-place rewrite "just works" in the top handful of editors people report issues with.
- The beta label on in-place re-injection can start coming off.

---

## v0.3 — optional cleanup

Opt-in polish of the transcript, using the user's own writing style — strictly additive, never required.

**What ships**
- **Optional LLM cleanup** (Claude Haiku / GPT-4o-mini) using the `[style].seed` already present in `profile.toml` (parsed but ignored since v0.1).
- **Second API key, optional.** Cleanup is off unless the user opts in and provides the key.

**What it enables**
- Transcripts that match the user's voice (short paragraphs, em-dashes, no hedging) without flattening their accent or word choice.
- A cleaner long-form dictation experience for those who want it — at a small extra per-minute cost they opt into.

**What success looks like**
- Cleanup is genuinely optional: the core loop and flywheel are unchanged with it off.
- With it on, output reads in the user's seeded style; substitution still runs first, so the guarantee holds.

---

## Backlog — someday, maybe

Tracked but unscheduled. Each has an existing seam in the v0.1 architecture so it does not require a rewrite when its time comes.

- **Per-app style profiles** — different style seeds per frontmost app, consumed by the v0.3 cleanup stage.
- **Local whisper.cpp mode** — zero API cost, fully offline transcription; `Transcriber` becomes a protocol with a local implementation, the rest of the pipeline is source-agnostic. ([ARCHITECTURE §6.6](../ARCHITECTURE.md#66-backlog-seams).)
- **Non-English vocabulary packs** — additive `[vocab]` content; `Substitutor` is already language-agnostic (it is string replacement).

---

## How to read the version numbers

- **v0.1** proves the bet (flywheel works, deterministically, with voice correction).
- **v0.1.1** removes install friction.
- **v0.2** makes the bet cheaper to keep (fewer corrections, better rewrites).
- **v0.3** adds optional shine without touching the bet.
- **Backlog** widens the bet (offline, multilingual, per-context) once the core is proven.

Nothing after v0.1 is allowed to weaken the v0.1 guarantee: substitution always runs, and a taught term is always corrected on the next dictation.
