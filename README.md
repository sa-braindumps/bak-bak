# Bak-Bak

*बक-बक* is Hindi for chattering. Bak-Bak is a voice dictation app for the Mac that remembers your corrections.

Hold **Control+Option**, speak, and let go. What you said gets typed wherever your cursor is, in any app. When it gets a word wrong, say "no, kubectl is kubectl" and it fixes it from then on. Corrections live in a plain text file you own.

## What it does

- Types into pretty much anything: browsers, Electron apps, regular Mac text fields.
- Learns your words. Say "no, X is Y" right after a dictation and it fixes the text it just typed, then applies that fix every time after. X has to be something it actually just typed, so a normal sentence like "actually the meeting is at 3pm" still gets typed as-is.
- Snippets. Say "my email" on its own and it types your full email address. Good for addresses, sign-offs, anything you type a lot.
- Voice commands for a few seconds after each dictation: "scratch that" deletes what was just typed, "new line" and "new paragraph" add line breaks, and "select that" highlights it.
- Can strip "um", "uh" and similar filler words. Off by default.
- Pick your own shortcut (Control+Option, Command+Option, and so on).
- Hold the keys to record, or switch to toggle mode: press once to start, again to stop.
- Press Esc to cancel a recording. Nothing gets sent to OpenAI and nothing is typed. The Esc doesn't leak through to the app you're in, so it won't close a dialog or stop a terminal command. You can also cancel from the menu bar.
- Keeps a history of every dictation in `~/.bak-bak/history.jsonl`.
- A dashboard window with your history, usage stats, dictionary and settings.
- Optional sounds when recording starts and stops.
- Uses `gpt-4o-mini-transcribe` with a language hint to cut down on made-up text when you're quiet.
- A small floating pill with a live waveform while you talk. Recording stops on its own after 60 seconds. If you're holding the keys, what you said still gets typed. In toggle mode it's thrown away, because by then you've probably forgotten it was on.
- Compresses audio to FLAC before upload so it's smaller and faster (falls back to WAV).
- Throws away recordings that are just silence.
- Can launch at login.
- On first run it asks for Accessibility access and opens settings if there's no API key yet.
- You bring your own OpenAI key. No subscription and no word limit. It costs about $0.003 a minute.

## Setup

You need:
- macOS 13 (Ventura) or later
- An OpenAI API key
- Swift 5.9+

### Build and install

```bash
git clone <repo-url> && cd bak-bak
./build-app.sh
open /Applications/Bak-Bak.app
```

The first time it runs, macOS will ask for **Microphone** and **Accessibility** permission. Allow both. The app then opens Dashboard → Settings so you can paste your API key.

## Usage

| Action | How |
|--------|-----|
| Dictate | Hold **Control+Option**, speak, let go (or in toggle mode, press once to start and again to stop) |
| Cancel | Press Esc while recording, or menu bar → Cancel Recording |
| Correct a word | Right after a dictation, say "no, X is Y" or "correction: X is Y" |
| Undo, new line, select | Right after a dictation, say "scratch that", "new line", "new paragraph" or "select that" |
| Add a snippet | `bak-bak snippet add "my email" "you@example.com"` |
| List or remove snippets | `bak-bak snippet list`, `bak-bak snippet remove "my email"` |
| Turn on filler removal | Set `remove_fillers = true` under `[cleanup]` in `~/.bak-bak/profile.toml` |
| Change the shortcut | Dashboard → Settings → Hotkey |
| See history | `swift run bak-bak history`, or Dashboard → Home |
| Check what's wrong | `swift run bak-bak doctor`, or menu bar → Run Doctor |
| Open the dashboard | Menu bar icon → Dashboard (or Cmd+,) |

Corrections and voice commands only count for a short window after each dictation (10 seconds by default, `correction_window_secs` in `profile.toml`). Anything said after that is typed as normal text.

## How it's put together

```
Sources/
  Pipeline/          # UI-free core: audio, transcription, vocab, history
  bak-bak/           # App shell: menu bar, hotkey, overlay, CLI commands
    Dashboard/       # SwiftUI dashboard views
```

It's a single Swift package with two dependencies (`TOMLKit` and `swift-argument-parser`). There's no Xcode project; `swift build` builds it. [ARCHITECTURE.md](./ARCHITECTURE.md) has the details.

## Your data

Everything lives in `~/.bak-bak/`:

| File | Format | What's in it |
|------|--------|--------------|
| `profile.toml` | TOML | API key, vocabulary, snippets, settings |
| `history.jsonl` | JSON Lines | Every dictation with its time, latency and model |

You can edit `profile.toml` by hand. Changes apply on the next dictation, and comments you add are kept when the app writes to the file.

## License

MIT
