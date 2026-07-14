# GDR Live Transcriber

**Record your tabletop RPG ("GDR") sessions on Linux and get a text transcript
of everything that was said — you on the microphone, your friends on Discord.**

The transcript (`transcript.txt`) is designed to be fed to an LLM afterwards to
generate a summary of the session.

How it works:

1. `./start.sh` records **two separate tracks** while you play:
   your **microphone** and your **system audio** (Discord voices, game sounds).
   Recording is very light — it doesn't slow down your game.
2. When you press **Ctrl+C**, both tracks are transcribed **locally and
   offline** with [whisper.cpp](https://github.com/ggerganov/whisper.cpp) and
   merged into one time-ordered transcript with speaker labels:

   ```
   [00:12:41] [ME] Entro nella cripta con la torcia accesa.
   [00:12:47] [DISCORD] Tira un tiro salvezza su destrezza!
   ```

Recording the two tracks separately (instead of mixing them) gives much better
transcription quality — whisper struggles when two voices overlap in the same
audio — and lets the transcript say who was talking.

The default language is **Italian** (`it`); whisper's multilingual models
support English and ~100 other languages too (see Options).

> Everything runs locally: after install, **no internet and no account needed**.

---

## Requirements

- **Ubuntu 24.04** (or derivative) with **PipeWire** (default on Ubuntu 24.04).
- Runs on **CPU** (no NVIDIA GPU required).
- ~2 GB free space for the model + build.

---

## 1. Install (once)

```bash
git clone git@github.com:Spuppateddu/GDR-Live-Transcriber.git
cd GDR-Live-Transcriber
./install.sh
```

`install.sh` does everything:
1. installs system dependencies (ffmpeg, pulseaudio-utils, build tools);
2. downloads and builds whisper.cpp;
3. **detects your CPU/RAM, recommends a model, and lets you choose** which to download.

### Which model?

Transcription happens **after** the session (not in real time), so you can
afford a bigger, more accurate model than a "live" tool could. Rough guide for
a 3-hour session:

| Model      | Accuracy | Transcription time (typical 8-core CPU) |
|------------|----------|------------------------------------------|
| `tiny`     | low      | minutes — only for testing               |
| `base`     | decent   | ~10 min                                  |
| `small`    | good     | ~30 min                                  |
| `medium`   | great    | ~1–2 h (**recommended** on 8+ cores, 16+ GB RAM) |
| `large-v3` | best     | can take longer than the session itself  |

> ⚠️ Do not use the `.en` models (e.g. `small.en`): those are **English only**.

You can skip the menu and force a model (handy to download a second one):

```bash
MODEL=medium ./install.sh
```

`transcribe.sh` automatically uses the best model you have installed; override
anytime with `MODEL=...`.

---

## 2. Before first use: set your default devices

The tool records the **default microphone** and the **default audio output**.
Open *Settings → Sound* and make sure the correct mic and speakers/headphones
are selected as the defaults. If you switch output device (e.g. plug in
headphones) do it **before** starting the session.

---

## 3. Record a session

```bash
./start.sh
```

- A timer shows that recording is running. Play normally.
- Press **Ctrl+C** when the session ends: transcription starts automatically
  (this part uses the CPU heavily — fine to leave it running and walk away).

Files are saved in `sessions/<date_time>/`:

```
sessions/2026-07-14_21-00-00/
├── transcript.txt   ← the merged transcript (feed this to your LLM)
├── mic.wav          ← your voice (backup)
├── discord.wav      ← system audio: friends + game (backup)
├── mic.srt          ← per-track subtitles with timestamps
└── discord.srt
```

### Options

```bash
LANG_CODE=en ./start.sh          # change language (default: it = Italian)
LANG_CODE=auto ./start.sh        # let whisper auto-detect the language
MODEL=small ./start.sh           # force a model for the final transcription
AUTO_TRANSCRIBE=0 ./start.sh     # record only, transcribe later (see below)
```

---

## 4. (Re-)transcribe a session

The `.wav` backups are kept, so you can always redo the transcript — for
example with a bigger model, or if you recorded with `AUTO_TRANSCRIBE=0`:

```bash
./transcribe.sh sessions/2026-07-14_21-00-00
MODEL=medium ./transcribe.sh sessions/2026-07-14_21-00-00   # higher quality
```

It also works on a single audio file (any format ffmpeg can read):

```bash
./transcribe.sh some-recording.mp3    # creates some-recording.txt
```

---

## 5. Summarize with an LLM

That part is up to you: upload `transcript.txt` to your favorite LLM and ask
for a session summary. The file starts with a comment explaining the
`[ME]` / `[DISCORD]` labels so the model has the context it needs.

---

## Troubleshooting

- **"whisper-cli not found"** → run `./install.sh` first.
- **"the microphone/system-audio track sounds silent"** → the wrong device is
  set as default; fix it in *Settings → Sound* and record again.
- **Friends' voices missing** → Discord must play through the **default**
  output device. Check *Settings → Sound* and Discord's own output setting.
- **Junk lines in the transcript** (e.g. "Sottotitoli a cura di...") → whisper
  hallucinates on music. If you play background music during sessions, keep it
  out of the recorded output (e.g. play it on another device) or just ignore
  those lines — the LLM summary won't care.
- **Transcription too slow** → use a smaller model:
  `MODEL=small ./transcribe.sh sessions/<dir>`.
- **Wrong language in the transcript** → pass `LANG_CODE=it` (or your
  language, or `auto`).
