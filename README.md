# Bak-Bak

*बक-बक* — Hindi for chattering. A Mac-native voice dictation app where your corrections persist and compound.

Hold **Control+Option**, speak, release. Your words appear wherever your cursor is — in any app. Corrections you teach it ("no, kubectl is kubectl") stick forever in a plain-text config file you own.

## Features

- **Universal paste** — Works in browsers, Electron apps, native macOS fields
- **Vocabulary that learns** — Say "no, X is Y" to teach corrections by voice
- **Transcription history** — Every dictation logged to `~/.bak-bak/history.jsonl`
- **Dashboard** — SwiftUI window with history timeline, usage insights, dictionary, and settings
- **Sound feedback** — Audio cues on hotkey press/release (configurable)
- **Low hallucination** — Uses `gpt-4o-mini-transcribe` with language hints
- **Floating overlay** — Wispr Flow-style pill showing Listening / Transcribing / Done
- **Bring your own key** — No subscriptions, no word limits, ~$0.003/minute

## Setup

### Requirements
- macOS 13 (Ventura) or later
- OpenAI API key
- Swift 5.9+

### Build and install

```bash
git clone <repo-url> && cd bak-bak
./build-app.sh
open /Applications/Bak-Bak.app
```

On first launch, grant **Microphone** and **Accessibility** permissions when prompted.

### Set your API key

```bash
swift run bak-bak setup
```

## Usage

| Action | How |
|--------|-----|
| Dictate | Hold **Control+Option**, speak, release |
| Correct | Say "no, X is Y" or "correction: X is Y" |
| View history | `swift run bak-bak history` or Dashboard > Home |
| Diagnostics | `swift run bak-bak doctor` |
| Dashboard | Menu bar icon > Dashboard (or Cmd+,) |

## Architecture

```
Sources/
  Pipeline/          # UI-free core: audio, transcription, vocab, history
  bak-bak/           # App shell: menu bar, hotkey, overlay, CLI commands
    Dashboard/       # SwiftUI dashboard views
```

Single Swift Package, two dependencies (`TOMLKit`, `swift-argument-parser`). No Xcode project — builds with `swift build`. See [ARCHITECTURE.md](./ARCHITECTURE.md) for details.

## Data

All data lives in `~/.bak-bak/`:

| File | Format | Contents |
|------|--------|----------|
| `profile.toml` | TOML | API key, vocabulary, settings |
| `history.jsonl` | JSON Lines | Every transcription with timestamp, latency, model |

## License

MIT
