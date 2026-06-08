# Cost Optimization Ideas

## 1. RMS Energy Gate (Silence Detection)

**What:** Compute RMS amplitude of the recorded audio before calling the API. If below a threshold, skip the API call entirely.

**Implementation:** In `AppCoordinator.stopRecording()`, after `audioRecorder.stopRecording()` returns data, compute RMS on the Float32 PCM buffer. If below ~0.01 RMS, treat as silence and return early.

**Saving:** Eliminates API calls on accidental presses and near-silent recordings. Biggest single saving.

**Product UX:**
- Add `.discarded` state to `RecordingOverlay` — gray pill, `mic.slash` icon, text "No speech detected", auto-dismiss in 1.2s
- Do NOT play the "Pop" release sound for discarded recordings (playing it with no text injected feels like a bug)
- Do not log discarded recordings to Dashboard history, or show a separate "skipped" tally

---

## 2. Minimum Duration Gate

**What:** Recordings shorter than ~300ms are almost always accidental hotkey taps. Gate on `audioData.count / (16000 * 4)` (seconds of Float32 at 16kHz).

**Implementation:** In `AppCoordinator.stopRecording()`, check duration before transcribing. Return `CoordinatorError.emptyRecording` (already silently dismissed) for sub-300ms recordings.

**Saving:** Eliminates API calls for accidental taps with no real cost to UX.

**Product UX:**
- Silent dismiss — no overlay change, just stop quietly. Calling attention to accidents is worse UX.
- Exception: if the user has fewer than 10 lifetime dictations, show a one-time "Hold to record" tooltip to teach the hold-to-talk model

---

## 3. Maximum Duration Cap

**What:** `RecorderError.recordingTooLong` exists in `AudioRecorder` but is never triggered. Without a cap, holding the hotkey for minutes is an unbounded cost.

**Implementation:** In `AudioRecorder.appendBuffer()`, track elapsed time since `startTime`. Auto-stop and throw `recordingTooLong` at 60 seconds.

**Saving:** Prevents runaway bills from accidental long holds. Main risk mitigation item.

**Product UX:**
- At ~50s: overlay pill color shifts red → amber (no text change, just color) as a soft warning
- At 60s: auto-play the "Pop" sound and transition to "Transcribing..." exactly as a manual release would — seamless handoff
- In the Dashboard history entry for that transcription: show a `60s max` badge so the user knows the transcript may be cut off

---

## 4. Audio Compression (FLAC)

**What:** Currently sending uncompressed WAV (Int16 PCM, ~32KB/s). OpenAI accepts FLAC, which is lossless and ~40–50% smaller.

**Implementation:** Replace `convertToWAV()` in `Transcriber.swift` with FLAC encoding via `AVAudioFile` + `kAudioFormatFLAC`. Update `Content-Type` to `audio/flac` and filename to `audio.flac`.

**Saving:** Faster uploads on slow connections. Smaller payloads. No quality tradeoff (lossless).

**Product UX:** Fully invisible to the user. Only side effect is slightly lower latency — no communication needed.

---

## 5. Model Already Optimal

`gpt-4o-mini-transcribe` at $0.003/min is already the cheapest OpenAI transcription model — half the cost of `whisper-1` ($0.006/min) and `gpt-4o-transcribe` ($0.006/min). Nothing to change here.

---

## New Overlay States Summary

| Scenario | State | Color | Icon | Text | Auto-dismiss |
|---|---|---|---|---|---|
| Silence detected | `.discarded` | Gray | `mic.slash` | "No speech detected" | 1.2s |
| Too short tap | *(silent dismiss)* | — | — | — | immediate |
| Near 60s limit | `.recording` (amber) | Amber | red dot | "Listening…" | — |
| Auto-stopped at 60s | `.transcribing` | Blue | spinner | "Transcribing…" | — |
| Truncated transcript | `.done` + badge | Green | checkmark | "Done" + `60s max` badge | 0.6s |

**Rule of thumb:** discards are neutral (gray), not errors (red). Errors are reserved for network failures, API key rejection, and rate limits.
