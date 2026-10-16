# Bak-Bak — Technical Specification

> *बक-बक* — Hindi for chattering. A Mac-native, bring-your-own-key voice dictation app whose one differentiator is that **your corrections persist and compound.**

This document specifies the behavior of **v0.1**. It is the contract: if the shipped binary disagrees with this document, one of them is a bug. Decisions are stated with their reasons so contributors can tell intentional constraints from accidental ones.

- For *why the system is shaped this way*, see [`ARCHITECTURE.md`](./ARCHITECTURE.md).
- For *what ships when*, see [`docs/ROADMAP.md`](./docs/ROADMAP.md).
- For *how to build and contribute*, see [`docs/CONTRIBUTING.md`](./docs/CONTRIBUTING.md).

---

## 1. Overview

Bak-Bak is a native macOS (13+) menu-bar app and CLI built around a single loop: hold `⌃⌥` (Control+Option), speak, release, and your words appear at the cursor in whatever app is focused. Audio is captured in memory and sent to the OpenAI transcription API (your key, no SDK, no word limits). Before the transcript is injected, Bak-Bak runs a **deterministic, case-insensitive string substitution** from a plain-text vocabulary file (`~/.bak-bak/profile.toml`) — so terms you have taught it once (your jargon, coworkers' names, `kubectl`) are always corrected. When Whisper mishears a *new* word, you fix it **by voice** ("no, X is Y"); the correction is written to that same file with a timestamp comment, the on-screen text is rewritten in place, and from then on the term is auto-corrected forever. No ML training, no hidden state, no cloud copy — just a config file the user owns, growing with use.

---

## 2. Core architecture

### 2.1 Component diagram

```
                          ┌──────────────────────────────────────────┐
                          │                  bak-bak                   │
                          │            (single Swift binary)           │
                          └──────────────────────────────────────────┘
                                  │                         │
                  app mode (NSApplication)          cli mode (ArgumentParser)
                                  │                         │
   ┌──────────────────────────────┴───────────┐   ┌─────────┴───────────────────┐
   │              Sources/App                  │   │         Sources/CLI         │
   │  ┌─────────────┐   ┌──────────────────┐   │   │  setup · doctor · vocab     │
   │  │ HotkeyMonitor│  │  StatusItem (4 st)│   │   │  (drives Pipeline + TOML)   │
   │  │ CGEvent/NSEv │  │  NSStatusItem     │   │   └─────────────────────────────┘
   │  └──────┬──────┘   └─────────▲────────┘   │                 │
   │         │ press/release       │ state      │                 │
   │  ┌──────▼─────────────────────┴────────┐   │                 │
   │  │       CorrectionController            │   │                 │
   │  │  (10s window, grammar match, rewrite) │   │                 │
   │  └──────┬───────────────────────▲───────┘   │                 │
   └─────────┼───────────────────────┼───────────┘                 │
             │ run()                  │ result                      │
   ┌─────────▼───────────────────────┴──────────────────────────────▼────────┐
   │                            Sources/Pipeline                              │
   │                                                                          │
   │   AudioRecorder  ─▶  Transcriber  ─▶  Substitutor  ─▶  Injector          │
   │   (AVAudioEngine,    (URLSession,      (TOML [vocab],   (AXUIElement /    │
   │    RAM buffer)        multipart        case-insensitive  CGEvent keys /   │
   │                       Whisper API)      replace)          NSPasteboard)   │
   │                                              ▲                            │
   └──────────────────────────────────────────────┼───────────────────────────┘
                                                  │ read/write
                                       ┌──────────▼───────────┐
                                       │  ProfileStore (TOMLKit│
                                       │  comment-preserving)  │
                                       │  ~/.bak-bak/profile.toml
                                       └──────────────────────┘
```

### 2.2 Primary data flow (the core loop)

```
1. ⌥ keyDown           → HotkeyMonitor → StatusItem: recording (red dot)
2. AVAudioEngine        → audio frames appended to in-RAM buffer
3. ⌥ keyUp             → HotkeyMonitor → stop capture, flush buffer
4. StatusItem: transcribing (pulse)
5. buffer → Transcriber → multipart POST → OpenAI Whisper → raw text
6. raw text → Substitutor (applies [vocab] map) → corrected text
7. corrected text → Injector → keystrokes at cursor (or clipboard fallback)
8. StatusItem: idle (dim mic)
9. CorrectionController opens a 10s window listening for a correction utterance
```

The audio buffer never touches disk. The only network call is step 5. See [§9 Privacy guarantees](#9-privacy-guarantees).

---

## 3. Feature specification (v0.1)

Each feature lists **Behavior**, **Edge cases**, and **Failure modes**. The differentiator is §3.3 + §3.4; everything else exists to make those two work.

### 3.1 Hold-to-record hotkey

**Behavior.** Holding `⌥` (Option, configurable via `[hotkey].trigger`) starts recording. The menu bar shows the recording state while the key is held. Releasing `⌥` stops recording and begins transcription. This is a *hold-and-release* gesture — not a toggle — so the user always knows recording is active because their finger is on the key.

**Edge cases.**
- **Tap with no speech.** In hold mode, a press shorter than 300 ms stops the mic and discards the audio silently — no API call, no error. Prevents accidental empty Whisper requests when `⌥` is used for its normal OS purpose.
- **Cancel.** While recording (either mode), **Esc** or the menu's *Cancel Recording* stops the mic and discards the audio: no API call, nothing injected, the overlay shows "Cancelled". Esc is swallowed by an event tap so it does not also reach the frontmost app; if the tap can't be created, a passive monitor still cancels but the app sees the key too. Once audio has been sent, cancel does nothing.
- **Hotkey during transcription.** Ignored. A new recording can start only after the previous one has been injected (or failed), so two runs can never inject out of order.
- **Toggle mode.** `[hotkey].recording_mode = "toggle"`: press once to start, again to stop and transcribe. Same cancel, cap and overlap rules. The rules live in one place, `Sources/Pipeline/RecordingStateMachine.swift`.
- **Hotkey used in another shortcut.** The hotkey matches only when *exactly* its modifiers are down (⌃⌥ doesn't fire while ⌃⌥⌘ is held). If a regular key is pressed while the hotkey is held (⌥→ to move by word, ⌘⇧4 for a screenshot), the recording that just started is discarded silently and the key passes through untouched.
- **Mic changes mid-recording** (AirPods connect or disconnect, a USB mic is unplugged). The audio engine stops, so Bak-Bak stops the recording and transcribes what was captured before the switch. A recording with no usable input fails to start with "Couldn't start the mic" instead of crashing.
- **Key held across app switch.** Recording continues; the transcript is injected wherever the cursor lands on release. (The user chose where to release.)
- **60-second cap.** Recording stops at 60 s (amber warning at 50 s). In hold mode the audio is transcribed, since holding the key that long is deliberate. In toggle mode it is discarded and the overlay shows "Stopped at 60s", since that is almost always a forgotten recording.

**Failure modes.**
- **Modifier-only detection proves flaky on some keyboards/layouts.** Documented fallback: a small Carbon `RegisterEventHotKey` registration. This is a last resort — the primary path is `CGEvent` tap + `NSEvent` global monitor.
- **Buffer grows beyond a safe RAM ceiling** (very long dictation): recording stops, error state shown with reason "recording too long", buffer flushed and transcribed up to that point. No crash, no disk spill.

### 3.2 Transcription (any OpenAI-compatible service)

**Behavior.** On key release, the in-memory audio buffer is encoded (FLAC, WAV fallback) and uploaded in a single multipart `URLSession` POST to `<base_url>/audio/transcriptions`. No SDK. The service and model come from `[transcription]` (§5.4c); the default is OpenAI `gpt-4o-mini-transcribe`, which is what v0.1 always used. Engines sit behind the `TranscriptionEngine` protocol so an on-device engine can be added without touching the rest of the pipeline. The round-trip latency is measured and stored for `bak-bak doctor`.

**Keys.** OpenAI uses `[general].api_key`. Any other service must have its own `[transcription].api_key`: the OpenAI key is **never** sent to another host. The key is checked *before* recording starts, so a missing key is reported immediately, not after the user has talked.

**Edge cases.**
- **No network** (offline, DNS failure, host unreachable). Error state, reason "No internet connection"; audio buffer discarded (never retried to disk). Other connection errors show the system's own description.
- **Slow response.** The transcribing state (pulse) persists for the full round-trip. A request timeout (default 30 s) trips the error state with reason "Transcription timed out".
- **Empty transcript returned.** Treated as a no-op — nothing injected, return to idle. No error (Whisper legitimately returns empty for silence/noise).

**Failure modes.**
- **401 / 403** → "API key rejected by <host>".
- **404** → "Model not found: <service's message>".
- **429** → "Rate limited or out of credit".
- **5xx** → "Transcription service error (<code>)". No automatic retry (avoids silently double-charging the user's key).
- **Any other 4xx** (400, 413, …) → "Request rejected: <service's message>".
- **200 without text** → "The service sent back no text".
- **No key for a non-OpenAI service** → "No API key for <host>. Add it in Dashboard → Settings → Transcription".

### 3.3 Deterministic vocabulary substitution — *the substitution layer*

**Behavior.** Before injection, the raw transcript passes through `Substitutor`, which applies every entry in `[vocab]` as a **case-insensitive whole-token string replacement**. Given `"cube cuttle" = "kubectl"`, the transcript `"run Cube Cuttle get pods"` becomes `"run kubectl get pods"`. This is the **guarantee** at the heart of the product: it is plain string replacement, not a hint to a model.

**Why deterministic replace and not Whisper `initial_prompt`.** Whisper's `initial_prompt` (prompt-priming) is best-effort and version-fragile — the same prompt yields different results across model versions and offers no guarantee a term is corrected. The flywheel is only worth shipping if a taught term is corrected *every time*. A deterministic replace from a file the user owns is that guarantee. Prompt-priming returns as an *optimization layer on top of* substitution in v0.2 (see [ROADMAP](./docs/ROADMAP.md)), never as a replacement for it.

**Prompt-priming (shipped as that optimization layer).** Each request's `prompt` is `Voice dictation. Vocabulary: <terms>.`, where the terms are the *intended* values from `[vocab]`, newest first, deduplicated ignoring case and capped at 150 words (`Sources/Pipeline/TranscriptionPrompt.swift`). With an empty `[vocab]` the prompt is just `Voice dictation.`, as before. Measured on synthetic speech with `gpt-4o-mini-transcribe`: invented names went from wrong to right ("Zentrophy" → "Zentrafy", "Corvex" → "Quorvex"), common tech terms were already right without it, and a term spoken very differently from its spelling ("buck buck" for "Bak-Bak") was not fixed by priming. That last case is what substitution is for.

**Matching rules.**
- Case-insensitive on the "heard" key; the "intended" value is inserted verbatim (preserves `kubectl` lowercase, `Nginx` capitalization).
- Matches respect token/word boundaries so `"nicks"` does not corrupt `"picnicks"`. Multi-word keys (`"cube cuttle"`) match across the space.
- Between the words of a key, a space, a hyphen or nothing are treated alike, because the model writes the same words differently from one dictation to the next: `"bug bug"` matches `bug bug`, `Bug-Bug` and `BugBug`. The same rule (`Sources/Pipeline/PhraseMatch.swift`) is used for snippet triggers and for checking that a correction's `X` was in the last dictation. Different *spellings* ("buck buck", "BugBuck") still need their own entries.
- Substitutions are applied longest-key-first so a longer phrase wins over a shorter overlapping one.
- The map is read fresh from `profile.toml` per transcription, so `bak-bak vocab add` and hand edits take effect on the very next dictation with no restart.

**Edge cases.**
- **Empty `[vocab]`** → transcript passes through unchanged.
- **Duplicate keys in the file** → last definition wins (TOML semantics); `bak-bak doctor` does not flag this in v0.1.
- **Key equals value** (no-op entry) → harmless, left in place.

**Failure modes.**
- **`profile.toml` malformed/unparseable** → substitution is skipped (raw transcript injected so the user is never blocked from dictating), and the error state shows reason "profile.toml unreadable — run bak-bak doctor". Dictation must never be held hostage by a bad config.

### 3.4 Voice correction — *the headline feature* (shipped as documented beta)

See [§7 Voice correction specification](#7-voice-correction-specification) for the full grammar, window, and rewrite mechanics. Summary:

**Behavior.** Immediately after any injection, a **10-second correction window** (`[correction].correction_window_secs`, default 10) opens. If the user's next utterance matches one of three correction grammars ("no, X is Y" / "correction: X is Y" / "actually X is Y"), Bak-Bak: (a) writes `X = Y` to `[vocab]` with a timestamp comment, then (b) rewrites the just-injected text in place via **backspace-delete + retype**. If the next utterance does not match a correction grammar, it is treated as a brand-new normal dictation — there is **no confirmation prompt** (a y/n loop would break the four-action setup promise and the "just talk" feel).

**The beta caveat (state it plainly to users).** *Voice correction is beta. The vocabulary always learns; in-place re-injection fidelity varies by app.* The flywheel — "the **next** dictation is correct" — is always true, because it depends only on the `[vocab]` write (§3.3), which is deterministic. The in-place rewrite of the *current* text is the part that can vary by app, and its failure never costs the user the learned correction.

### 3.5 Text injection at cursor

**Behavior.** Corrected text is pasted at the cursor: Bak-Bak snapshots the clipboard (every item, every type), puts the text on it marked `org.nspasteboard.TransientType` so clipboard managers skip it, posts ⌘V via `CGEvent`, and restores the snapshot 0.5 s later. The restore is skipped if the clipboard changed in the meantime (the user copied something new). Logic lives in `Sources/Pipeline/ClipboardSnapshot.swift`.

When Accessibility permission is **denied**, synthesized keystrokes are impossible, so the text is left on the clipboard (not restored) and the overlay says **"Copied to clipboard. Press ⌘V to paste."** The user is never left wondering why nothing appeared at the cursor, and the dictation is never lost.

**Edge cases.**
- **No focused text element** (e.g. focus on a non-text control) → clipboard fallback with the same explicit message. *Not yet implemented: today the ⌘V is sent regardless.*
- **Secure input field** (password fields with secure event input) → clipboard fallback; secure fields refuse synthesized input by OS design. *Not yet implemented.*

**Failure modes.**
- **AX insertion partially succeeds** in a quirky app → this is exactly why the *correction* path uses backspace+retype rather than AXValue (see [§7.4](#74-in-place-rewrite-mechanics)).
- **Accessibility revoked mid-session** → next injection detects denial and switches to clipboard fallback; no crash.

### 3.6 Menu bar (4 states)

Specified fully in [§6](#6-menu-bar-specification). Exactly four states — idle, recording, transcribing, error. There is deliberately **no fifth "learned" state**: the on-screen text rewrite *is* the feedback that a correction happened.

### 3.7 CLI commands

Specified fully in [§4](#4-cli-specification). Exactly four command groups in v0.1: `setup`, `doctor`, `vocab add`, `vocab list`. The app and CLI are the same binary.

---

## 4. CLI specification

The CLI is built with Apple's `ArgumentParser`. All commands operate on `~/.bak-bak/profile.toml`. `--help` is provided free by ArgumentParser for every subcommand.

### 4.1 `bak-bak setup`

A linear, **exactly-four-action** flow. It must not balloon into a wizard — four steps, in order, stopping on failure.

| # | Action | Behavior | On failure |
|---|--------|----------|------------|
| 1 | **Paste key** | Prompt for the OpenAI API key (input not echoed). | — |
| 2 | **Live validate** | Make one minimal authenticated call to confirm the key works. | **Stop. Do not advance.** Print "API key rejected" and exit non-zero. |
| 3 | **Confirm hotkey** | Show the default (`⌥`), accept an override, write `[hotkey].trigger`. | Re-prompt once, then keep default. |
| 4 | **Grant Accessibility** | Open the Accessibility pane and **poll until permission is detected**. | Print the right-click-Open / Accessibility instructions; keep polling until granted or user quits. |

**Rules.**
- The order is fixed. Step 2 is a hard gate: a bad key stops the flow so the user never proceeds to a half-working install.
- On first success, writes a fresh `profile.toml` with the commented example vocabulary (see [§5.6](#56-default-file)).
- Output also prints the **unsigned-build workaround** (right-click → Open) so the user has it even if they missed it in the README.

**Output (success, abridged):**
```
bak-bak setup
  [1/4] API key ......... pasted
  [2/4] Validating ...... ok (gpt key accepted)
  [3/4] Hotkey .......... ⌥ Option   (press enter to keep)
  [4/4] Accessibility ... waiting… granted ✓

Setup complete. Hold ⌥ anywhere and start talking.
Note: first launch may say "can't be opened" — right-click the app → Open.
```

### 4.2 `bak-bak doctor`

Prints a diagnostic checklist. Read-only; never modifies the profile. Exit code is non-zero if any required check fails.

Reports, in order:
1. **Mic access** — granted / denied
2. **Accessibility** — granted / denied (clipboard-fallback note if denied)
3. **Key validity** — one live check, ok / rejected
4. **Hotkey registration** — registered / failed (and which trigger)
5. **Last transcription latency** — in **ms** (or "none yet")
6. **Vocab entry count** — number of `[vocab]` entries
7. **Last 5 corrections** — parsed from the `# learned <timestamp>` comments in `profile.toml`

**Output (example):**
```
bak-bak doctor
  mic access ............ granted
  accessibility ......... denied  (text will go to clipboard)
  api key ............... ok
  hotkey ................ registered (⌥ option)
  last latency .......... 812 ms
  vocab entries ......... 14
  recent corrections:
    2026-06-08T10:23:11Z  cube cuttle → kubectl
    2026-06-07T19:02:40Z  nicks → Nginx
    ...
```

### 4.3 `bak-bak vocab add "<heard>" "<intended>"`

Appends `"<heard>" = "<intended>"` to `[vocab]` in `profile.toml`. Two positional arguments, both required, both quoted (they may contain spaces).

- Comment-preserving write (TOMLKit) so existing learned-correction comments survive.
- If `<heard>` already exists, the value is updated in place and a `# updated <timestamp>` comment is added.
- Takes effect on the next dictation; no restart.

**Output:** `added: "cube cuttle" → "kubectl"`

### 4.4 `bak-bak vocab list`

Pretty-prints the current `[vocab]` table aligned in two columns. Read-only.

**Output:**
```
heard          intended
─────────────  ────────
cube cuttle    kubectl
nicks          Nginx
rack bak       Bak-Bak
```

This command is the proof that there is **no hidden state** — what the app knows is exactly what this prints, which is exactly what is in the file.

### 4.5 `bak-bak snippet`

Manages the `[snippets]` table (§5.1b). Three subcommands, all comment-preserving (TOMLKit), all taking effect on the next dictation with no restart:

- **`bak-bak snippet add "<trigger>" "<expansion>"`** — appends or updates `"<trigger>" = "<expansion>"`. Two positional arguments, both quoted (they may contain spaces; `<expansion>` may be multi-line). If `<trigger>` exists, its value is updated in place.
  **Output:** `added: "my email" → "you@example.com"`
- **`bak-bak snippet list`** — pretty-prints the current `[snippets]` table in two columns (multi-line expansions show their first line with an ellipsis). Read-only.
- **`bak-bak snippet remove "<trigger>"`** — removes the entry for `<trigger>`. No-op if absent.
  **Output:** `removed: "my email"`

Like `vocab list`, `snippet list` is proof of no hidden state — it prints exactly what is in the file.

### 4.6 `bak-bak transcribe <file>`

Runs an audio file (wav, aiff, m4a, mp3, flac…) through the same steps as a dictation (the configured service and model, the vocabulary prompt, then fillers, `[vocab]` and `[snippets]`) and prints the final text instead of typing it. Only cursor injection is skipped.

- `--verbose` also prints the service, model, latency, prompt and raw transcript.
- `--profile <path>` uses another `profile.toml`, for testing without touching the real one.

This is how the transcription path is tested end to end without a microphone, e.g. with audio from `say -o test.aiff "…"`.

---

## 5. `profile.toml` specification

Location: `~/.bak-bak/profile.toml`. Format: TOML, edited via a **comment-preserving** writer (TOMLKit). Every key below is documented with type, default, and constraints.

### 5.1 `[vocab]`

| Key form | Type | Default | Constraints |
|----------|------|---------|-------------|
| `"<heard>" = "<intended>"` | string → string | `{}` (empty) | Keys matched case-insensitively, longest-first, on token boundaries. Values inserted verbatim. Learned entries are preceded by a `# learned <ISO-8601-Z>` comment. |

### 5.1b `[snippets]`

| Key form | Type | Default | Constraints |
|----------|------|---------|-------------|
| `"<trigger phrase>" = "<expansion>"` | string → string | `{}` (empty) | A spoken **whole utterance** matching `<trigger phrase>` is replaced by `<expansion>`. Matching is case-insensitive, trimmed, tolerant of a trailing punctuation mark, and longest-trigger-first. Embedded/mid-sentence expansion is **not** done (predictability). Expansions may be multi-line TOML strings (e.g. an address block). Like `[vocab]`, this is deterministic string replacement, not a model call. |

The snippet stage runs **after** `[vocab]` substitution and **before** injection. Edit `[snippets]` by hand or via `bak-bak snippet` (§4.5); it is read fresh per dictation, so changes take effect on the next dictation with no restart.

### 5.2 `[style]`

| Key | Type | Default | Constraints |
|-----|------|---------|-------------|
| `seed` | multi-line string | absent | **Not consumed in v0.1.** Reserved for the v0.3 LLM-cleanup layer (style-seeded system prompt). Present in the file as documentation of intent; ignored by the pipeline until v0.3. |

### 5.3 `[hotkey]`

| Key | Type | Default | Constraints |
|-----|------|---------|-------------|
| `trigger` | string | `"option"` | One of the modifier identifiers (`"option"`, etc.). Read at launch; changing it requires a relaunch in v0.1. |

### 5.4 `[correction]`

| Key | Type | Default | Constraints |
|-----|------|---------|-------------|
| `correction_window_secs` | integer | `10` | The named constant for the voice-correction window. Configurable so power users can shorten/lengthen it. `0` disables voice correction (vocabulary still applies; the window simply never opens). |

### 5.4b `[cleanup]`

| Key | Type | Default | Constraints |
|-----|------|---------|-------------|
| `remove_fillers` | bool | `false` | When `true`, a fixed set of disfluency tokens (`um, umm, uh, uhh, erm, er, ah, hmm, mm`) is stripped from the raw transcript as **whole tokens only** (case-insensitive), spacing/punctuation is tidied, and a leading-filler-stripped first letter is re-capitalized. This is deterministic string surgery — not a model call. Real words (`like`, `so`, `you know`) are never removed, and substrings are never gutted (`summary` keeps its `um`). Off by default. |

| `polish` | bool | `false` | When `true`, each dictation of 4+ words (not snippet triggers, not voice commands or corrections) is sent to OpenAI `gpt-4o-mini` with the OpenAI key to fix punctuation, capitals and paragraph breaks and drop fillers and false starts, keeping the speaker's words. Toggle from the menu bar (**Polish Text**) or Dashboard → Settings. Adds ~0.5–1 s. |

**Polish safety.** The transcript is sent inside `<transcript>` tags with instructions that it is speech to clean, never a request. Because a model can still answer instead (in testing, "write me a poem about the ocean" came back as a poem before this was added), a reply with noticeably more words than the input is rejected in code and the unpolished text is used. Any failure (timeout, HTTP error, no OpenAI key) also falls back to the unpolished text, so polish can never lose a dictation. `[vocab]` runs after polish, so taught terms stay correct.

The cleanup stage runs on the raw transcript **before** `[vocab]` substitution, so vocabulary still matches the cleaned text. Unknown keys in `[cleanup]` are preserved on write (this table is an extension point).

### 5.4c `[transcription]`

| Key | Type | Default | Constraints |
|-----|------|---------|-------------|
| `base_url` | string | `"https://api.openai.com/v1"` | Any OpenAI-compatible API root; `/audio/transcriptions` is appended. Must be http(s). |
| `model` | string | `"gpt-4o-mini-transcribe"` | Sent as-is. Groq: `whisper-large-v3-turbo`. |
| `api_key` | string | *(absent)* | Required for any host other than `api.openai.com`. Removed when switching back to OpenAI in the Dashboard. |
| `language` | string | `"en"` | `en`, `hi`, `hinglish` or `auto`. `en`/`hi` are sent as the API's `language` field; `hinglish`/`auto` leave it out so the model detects. Unknown values fall back to `en`. |

**Hinglish.** The transcription models always write Hindi speech in Devanagari; telling them to use Roman letters does nothing (tested). So Hinglish mode (1) sends an example of Roman Hinglish speech as the prompt, which measurably helps them hear English words inside Hindi ("deck" instead of "देख"), and (2) converts the Devanagari to everyday Roman spelling with `HinglishRomanizer`: silent-"a" deletion, the system's ICU transliteration, a small spelling map and a short list of common English loanwords. The conversion runs before commands, corrections, fillers and `[vocab]`, so all of those work the same in Hinglish, and anything it spells oddly ("vala", "han") is fixed by teaching `[vocab]`. It aims for readable everyday Hinglish, not perfect transliteration.

The whole table is optional; a missing table means the OpenAI default. The Dashboard → Settings → Transcription card offers presets (OpenAI mini, OpenAI full, Groq) and a Custom option.

### 5.5 Defaults and constraints summary

- A **missing file** is equivalent to: empty `[vocab]`, empty `[snippets]`, no `[style].seed`, `[hotkey].modifiers = "control+option"`, `[hotkey].recording_mode = "hold"`, `[correction].correction_window_secs = 10`, `[cleanup].remove_fillers = false`. `setup` creates the file from `ProfileStore.defaultTemplate` on first run only; re-running `setup` never overwrites an existing profile, it only updates `api_key`.
- A **malformed file** does not block dictation (raw transcript is injected) and surfaces in the error state and `bak-bak doctor`.
- **Comments are load-bearing**: the `# learned <timestamp>` comments are how `doctor` reconstructs correction history. There is no separate `corrections.log` — history lives in these comments. This is why the TOML writer **must** preserve comments.

### 5.6 Default file (written by `setup`)

```toml
# ~/.bak-bak/profile.toml
# This file is yours. Edit it, diff it, put it in git. There is no hidden state.

[vocab]
# Teach Bak-Bak a term once and it is corrected forever.
# Format:  "what whisper heard" = "what you meant"
# Example (uncomment or copy your own):
# "cube cuttle" = "kubectl"
# "nicks"       = "Nginx"

[snippets]
# Speak a whole trigger phrase, get the expansion. Whole-utterance only.
# Format:  "trigger phrase" = "expansion text"
# Example (uncomment or copy your own):
# "my email"   = "you@example.com"
# "my address" = """
# 123 Main St
# Springfield
# """

[cleanup]
# Deterministic filler removal (um, uh, erm, …). Off by default.
remove_fillers = false

[style]
# Reserved for optional LLM cleanup (v0.3). Ignored in v0.1.
# seed = """
# I write in short paragraphs. I use em-dashes. I don't hedge.
# """

[hotkey]
trigger = "option"

[correction]
correction_window_secs = 10
```

---

## 6. Menu bar specification

Implemented with `NSStatusItem` and four template images plus hover tooltip strings. **No animation framework** — the "pulse" is a simple alternating template image. Exactly four states; no more.

| State | Icon | When | Hover text |
|-------|------|------|------------|
| **idle** | dim mic | default; nothing happening | `Bak-Bak — hold ⌥ to talk` |
| **recording** | red dot | lit **while the hotkey is held** | `Recording… release ⌥ to transcribe` |
| **transcribing** | pulsing mic | during the Whisper API round-trip | `Transcribing…` |
| **error** | red ✗ | on any failure; auto-clears after **5 s** | the failure reason (e.g. `API key rejected`) |

### 6.1 Transitions

```
idle ──(⌥ down)──▶ recording ──(⌥ up)──▶ transcribing ──(text injected)──▶ idle
  ▲                    │                       │
  │                    │ (tap too short)       │ (any failure)
  └────────────────────┴───────────────────────┴──▶ error ──(5s elapsed)──▶ idle
```

- **recording** is lit for exactly as long as the key is held — it is the user's real-time confirmation that audio is being captured.
- **error** always carries a reason on hover and always self-clears after 5 seconds back to idle.
- There is intentionally **no "learned" state**. When a voice correction succeeds, the feedback is the text being rewritten on screen — adding a fifth icon state would be redundant noise.

---

## 7. Voice correction specification

This is the headline feature. It is shipped as a **documented beta**: the learning is always reliable; the in-place rewrite is the part that varies by app.

### 7.1 The window

After any injection, `CorrectionController` opens a listening window of `[correction].correction_window_secs` seconds (default 10). During the window, the next dictation is first tested against the correction grammars before being treated as normal dictation. `correction_window_secs = 0` disables the window entirely.

### 7.2 Grammar patterns

Exactly three patterns are recognized in v0.1. Each captures an `X` (the heard term) and a `Y` (the intended term):

| Pattern | Example utterance | Captures |
|---------|-------------------|----------|
| `no, X is Y` | "no, cube cuttle is kubectl" | X=`cube cuttle`, Y=`kubectl` |
| `correction: X is Y` | "correction cube cuttle is kubectl" | X=`cube cuttle`, Y=`kubectl` |
| `actually X is Y` | "actually nicks is Nginx" | X=`nicks`, Y=`Nginx` |

Matching is case-insensitive on the leading keyword and on the connective `is`. Leading punctuation/filler ("no," / "correction:" / "actually") is stripped. Everything between the keyword and ` is ` is `X`; everything after is `Y`. Trailing sentence punctuation and wrapping quotes are trimmed from both (`Bak-Bak.` → `Bak-Bak`; a dot inside a word, as in `Node.js`, stays).

People start ordinary sentences with "no" and "actually" all the time, so a pattern match only counts as a correction when it also looks like a word fix:

- `X` and `Y` are each at most 4 words.
- `X` is not a lone pronoun (`it`, `that`, `this`, …) and differs from `Y` beyond case.
- `X` appears, as whole words and ignoring case, in the text that was just injected.

"Actually the meeting is at 3pm" right after dictating "Send the invite for Friday" fails the last rule and is typed as normal dictation. (How this parser is structured so contributors can add patterns is documented in [CONTRIBUTING §7](./docs/CONTRIBUTING.md#7-how-voice-correction-grammar-patterns-are-parsed).)

### 7.3 Match vs no-match behavior

- **Match.**
  1. Write `"X" = "Y"` into `[vocab]` with a `# learned <ISO-8601-Z>` comment (the durable, always-reliable part — this powers the flywheel).
  2. Rewrite the just-injected on-screen text in place (the beta part — see §7.4).
  3. Return to idle.
- **No match.** The utterance is treated as a **new normal dictation** — transcribe → substitute → inject. **No confirmation loop, no y/n prompt.** Requiring confirmation would contradict the four-action setup ethos and make every dictation feel interrogated.

### 7.4 In-place rewrite mechanics

The rewrite uses **backspace-delete + retype**, *not* AXValue replacement:

1. Compute the length of the text that was just injected (tracked by `CorrectionController` from the prior injection).
2. Synthesize that many **backspace** keystrokes via `CGEvent` to delete the wrong text.
3. Synthesize keystrokes to type the corrected text: the **previously injected text** with the new `X → Y` entry applied. (Not the correction utterance. "run cube cuttle get pods" + "no, cube cuttle is kubectl" → "run kubectl get pods".)

**Why backspace+retype and not AXValue.** Setting `AXValue` directly behaves differently across apps and causes artifacts in editors with vim mode, autocomplete, or custom text engines (text reordered, duplicated, or autocompletions triggered). Synthesized backspaces + typed characters are what a human would do and are universally compatible. This is the same reason §3.5's *correction* path does not reuse a naive AXValue set.

### 7.5 The "focus changed" safety rule

If the length of the prior injection **cannot be determined** — most commonly because focus changed between the dictation and the correction — Bak-Bak **skips the rewrite entirely**: nothing is deleted and nothing is typed (retyping the whole fixed text into whatever now has focus would just duplicate it somewhere else). Focus counts as changed when the frontmost app differs from the one the text was injected into. It must **never** issue backspaces blindly, because that would eat surrounding text the user did not dictate. Losing the in-place rewrite is acceptable; eating the user's other text is not. The `[vocab]` write still happens, so the flywheel is intact regardless.

### 7.6 Caveats (surface these to users verbatim)

> **Voice correction is beta. The vocabulary always learns; in-place re-injection fidelity varies by app.**

- The learned correction (next dictation is right) is a **guarantee**.
- The in-place rewrite of the current text is **best-effort** and may be skipped (§7.5) or imperfect in unusual editors.

### 7.7 Voice editing commands

During the same correction window (§7.1), the next utterance is also tested against a small set of **deterministic editing commands** *before* it is tested as a correction or treated as normal dictation. These are whole-utterance matches, case-insensitive, tolerant of a trailing punctuation mark; anything that does not match falls through to the correction grammar and then to normal dictation. Parsing lives in `Sources/Pipeline/CommandGrammar.swift` (mirroring `CorrectionGrammar`).

| Utterance | Action |
|-----------|--------|
| `scratch that` / `delete that` / `undo that` | Backspace-delete the just-injected text. |
| `new line` | Type one newline. |
| `new paragraph` | Type two newlines. |
| `select that` / `select last sentence` | Select the just-injected text backward (Shift+LeftArrow ×N). |

The interception order in the correction window is: **editing command → voice correction → normal dictation**. The first match wins and short-circuits; a handled command/correction is **not** injected as normal text.

**Safety (the §7.5 rule applies).** `scratch that` and `select that` operate over the prior-injection length tracked by `CorrectionController`. If that length is unknown (e.g. focus changed), they are **no-ops** — Bak-Bak never backspaces or selects blindly into the user's surrounding text. `new line` / `new paragraph` only append, so they are always safe.

(Rewrite-by-meaning commands such as "make that more formal" are **not** part of v0.1 — they require the LLM cleanup layer and are deferred.)

---

## 8. Error handling

Every error funnels to the single **error** menu-bar state (red ✗, 5 s, reason on hover) and, where a CLI command is involved, to a non-zero exit with a printed reason. Audio is **never** persisted on any error path.

| Error | Trigger | What the user sees | Recovery |
|-------|---------|--------------------|----------|
| `no network` | transcription POST fails to connect | error ✗, hover "no network" | retry by dictating again |
| `transcription timed out` | Whisper request exceeds 30 s | error ✗, hover "transcription timed out" | retry |
| `API key rejected` | 401 from Whisper / setup validate | error ✗ (app) or stop+exit (setup) | `bak-bak setup` |
| `rate limited or out of quota` | 429 | error ✗, hover reason | wait / check OpenAI quota |
| `Whisper API error (5xx)` | 5xx | error ✗, hover reason | retry later (no auto-retry) |
| `recording too long` | RAM buffer ceiling hit | error ✗; partial audio is still transcribed | dictate in shorter bursts |
| `profile.toml unreadable` | malformed TOML | error ✗; **raw transcript still injected** | fix file / `bak-bak doctor` |
| `copied to clipboard` | Accessibility denied / no text target | menu bar note (not a red ✗ — it's a fallback, not a failure) | grant Accessibility for cursor injection |
| `mic access denied` | OS mic permission missing | error ✗, hover reason | grant in System Settings; `bak-bak doctor` confirms |

**Principle:** a bad config or a denied permission degrades gracefully (clipboard fallback, raw transcript) — it never blocks the user from dictating, and it never costs them a learned correction.

---

## 9. Privacy guarantees

These are promises the architecture enforces, not aspirations.

| Resource | Touches disk? | Touches network? | Stays in RAM? |
|----------|---------------|------------------|---------------|
| **Audio** | **Never.** Captured by `AVAudioEngine` into a RAM buffer, flushed on release, discarded after transcription (and on every error path). | Only as the multipart body of the single Whisper POST. | Yes — buffer lives in RAM and only there. |
| **Transcript** | Not written by Bak-Bak (it is injected into whatever app you target — that app may save it; Bak-Bak does not). | Returned from the Whisper POST. | Held transiently for substitution + injection. |
| **API key** | Stored once, locally, set up via `bak-bak setup`. | Sent only to OpenAI as the Authorization on the Whisper POST. | — |
| **Vocabulary / corrections** | **Yes — `~/.bak-bak/profile.toml`, plain text, user-owned.** | **Never.** No cloud copy, no sync. | Read fresh per dictation. |

- **No hidden state, no ML training.** Everything Bak-Bak "knows" is in `profile.toml`, which `bak-bak vocab list` prints in full.
- **One network surface.** The Whisper POST is the only outbound call. This is deliberate — it keeps latency reporting in `doctor` trivial and makes the privacy story auditable.
- **The "never written to disk" audio promise is structural:** `AVAudioEngine` streams to a RAM buffer; there is no code path that writes audio to a file, including error and "recording too long" paths.

---

## 10. Testing approach

The pipeline is isolated in `Sources/Pipeline/` precisely so it can be tested independently of UI and Accessibility. See [CONTRIBUTING §6](./docs/CONTRIBUTING.md#6-testing-requirements-before-pr) for the contributor-facing checklist.

### 10.1 Unit tests (no OS permissions, no network — must run in CI)

- **Substitutor** — the highest-value tests, because substitution is the guarantee:
  - case-insensitive matching; verbatim value insertion
  - token-boundary correctness (`nicks` does not hit `picnicks`)
  - multi-word keys; longest-key-first ordering
  - empty/missing vocab passthrough; malformed-config passthrough (raw text injected)
- **Correction grammar parser** — each of the three patterns; case-insensitive keyword/connective; filler/punctuation stripping; correct X/Y capture; non-matching utterances classified as normal dictation.
- **ProfileStore (TOML)** — round-trip read/write **preserving comments**; `# learned <ts>` comment written on a learned correction; `doctor`'s "last 5 corrections" parsing from comments; malformed file handled without throwing into the dictation path.
- **Length tracking for rewrite** — given a known prior injection, the correct backspace count is computed; "focus changed / length unknown" yields **skip-delete** (the §7.5 safety rule) rather than a guessed count.

### 10.2 Integration tests (require OS permissions / a stub server)

- **Transcriber** against a **stubbed Whisper endpoint**: multipart body shape, latency capture, and mapping of 401/429/5xx/timeout to the correct error reasons. Real OpenAI calls are not run in CI.
- **Injector**: AX insertion into a known text field; clipboard fallback when Accessibility is denied (and the explicit "copied to clipboard" message). Requires Accessibility — run on a developer machine / gated CI runner, not unit CI.
- **HotkeyMonitor**: modifier-only press/release detected; `⌥`+other-key passes through; tap-too-short discarded. Requires event-tap permission.
- **End-to-end correction loop** (manual / scripted on a dev machine, mirrors the demo): wrong text → "no, X is Y" → in-place rewrite → repeat term → silent auto-correct → `bak-bak vocab list` shows the entry. This is the 90-second demo, used as the acceptance test for the differentiator.

### 10.3 What is explicitly not tested in CI

Real network calls to OpenAI, real Accessibility injection across third-party apps, and per-app rewrite fidelity (the documented-beta surface) are validated manually. CI guarantees the deterministic core (substitution, grammar parsing, TOML round-trip, length math) — i.e. the parts the flywheel guarantee depends on.
