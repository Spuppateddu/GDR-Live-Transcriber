# GDR Live Transcriber

**Record your tabletop RPG ("GDR") sessions on Linux and get a text transcript
of everything that was said — you on the microphone, your friends on Discord.**

The transcript (`transcript.txt`) is designed to be fed to an LLM afterwards to
generate a summary of the session.

How it works:

1. `./start.sh` records **two separate tracks** while you play:
   your **microphone** and your **PC audio** (Discord voices, game sounds).
   Recording is very light — it doesn't slow down your game.
2. While you play, a **live draft** of the transcript scrolls in the terminal,
   about 30 seconds behind — handy to re-read a name or what was just said.
   It uses a small fast model, so it's rough; the accurate transcript comes at
   the end.
3. When you press **Ctrl+C**, both tracks are transcribed **locally and
   offline** with [whisper.cpp](https://github.com/ggerganov/whisper.cpp) and
   merged into one time-ordered transcript with speaker labels:

   ```
   [00:12:41] [ME] I enter the crypt with my torch lit.
   [00:12:47] [PC] Roll a Dexterity saving throw!
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
- Runs on **CPU** (no NVIDIA GPU required). With an NVIDIA GPU and the CUDA
  toolkit installed, `install.sh` builds GPU-accelerated automatically:
  transcription gets ~10-20x faster and the live draft can use the big
  `medium` model instead of `base`.
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

If you pick a big model (`small` or larger), `install.sh` also downloads the
small `base` model (~140 MB) — that one powers the live draft during recording.
It also downloads a tiny VAD (voice activity detection) model that skips
non-speech: without it, the long silences on the mic track while friends talk
make whisper hallucinate repeated sentences.

### Which model?

Transcription happens **after** the session (not in real time), so you can
afford a bigger, more accurate model than a "live" tool could. Rough guide for
a 3-hour session:

| Model      | Accuracy | Transcription time (typical 8-core CPU) |
|------------|----------|------------------------------------------|
| `base`     | decent   | ~10 min                                  |
| `small`    | good     | ~30 min                                  |
| `medium`   | great    | ~1–2 h (**recommended** on 4+ cores, 12+ GB RAM) |
| `large-v3` | best     | can take longer than the session itself  |

> ⚠️ Do not use the `.en` models (e.g. `small.en`): those are **English only**.

You can skip the menu and force a model (handy to download a second one):

```bash
MODEL=medium ./install.sh
```

`transcribe.sh` automatically uses the best model you have installed; override
anytime with `MODEL=...`.

---

## 2. Audio devices: you pick them when you start

`start.sh` **lists your audio devices and asks which two to record**, so you
never depend on the system default being the right one (it often isn't — a
webcam mic tends to grab it):

- **Microphone** → your voice, the `[ME]` track. Choose from the real inputs.
- **PC audio** → Discord + game, the `[PC]` track. Choose the *monitor* of the
  output you actually **listen through**: if your friends' voices come out of
  your headset, pick the headset's monitor, not the speakers'.

The current system defaults are pre-selected, so pressing Enter twice keeps the
old behaviour. Your choice is saved in `config.env` with the other answers; if
that device is not connected the next time (USB mic unplugged, headset off),
the script says so and asks again instead of recording silence.

You can also preset them and skip the questions:

```bash
pactl list short sources            # see the exact names
MIC_SRC=alsa_input.usb-Blue_Microphones_Yeti_Stereo_Microphone_REV8-00.analog-stereo \
PC_SRC=alsa_output.pci-0000_00_1f.3.analog-stereo.monitor ./start.sh
```

---

## 3. Record a session

```bash
./start.sh
```

The first time, it **asks a few questions** (microphone, PC audio, language,
model, live draft on/off)
and lists every valid answer — just press **Enter** at each to take the default,
so there's nothing to memorize. At the end it offers to **remember your answers**
in a `config.env` file. On every later run it then **shows your saved setup and
asks whether to keep it or change it** — keep to start recording right away, or
change to answer the questions again. Delete `config.env` to wipe it entirely.
The environment variables below still work and override the saved answers.

- A timer shows that recording is running. Play normally.
- Every ~30 seconds, the **live draft** prints what was just said, with the
  same `[ME]` / `[PC]` labels as the final transcript. It's a quick
  low-quality draft to jog your memory — don't worry if it garbles words.
- Press **Ctrl+C** when the session ends: transcription starts automatically
  (this part uses the CPU heavily — fine to leave it running and walk away).

Files are saved in `sessions/<date_time>/`:

```
sessions/2026-07-14_21-00-00/
├── transcript.txt   ← the merged transcript (feed this to your LLM)
├── live.txt         ← the live draft (rough; superseded by transcript.txt)
├── mic.wav          ← your voice (backup)
├── pc.wav           ← PC audio: friends + game (backup)
├── mic.srt          ← per-track subtitles with timestamps
└── pc.srt
```

### Options

```bash
MIC_SRC=... PC_SRC=... ./start.sh # preset the devices (pactl list short sources)
LANG_CODE=en ./start.sh          # change language (default: it = Italian)
LANG_CODE=auto ./start.sh        # let whisper auto-detect the language
MODEL=small ./start.sh           # force a model for the final transcription
AUTO_TRANSCRIBE=0 ./start.sh     # record only, transcribe later (see below)
LIVE=0 ./start.sh                # no live draft, just the timer
LIVE_CHUNK=20 ./start.sh         # live draft updates every 20 s instead of 30
LIVE_MODEL=base ./start.sh       # force the model used for the live draft
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
`[ME]` / `[PC]` labels so the model has the context it needs.

---

## Troubleshooting

- **"whisper-cli not found"** → run `./install.sh` first.
- **"the microphone/PC-audio track sounds silent"** → the wrong device was
  picked. Start again, answer `n` at *Use this setup?* and choose another one.
- **Friends' voices missing** → the `[PC]` device must be the monitor of the
  output Discord actually plays through. Check Discord's own output setting,
  then pick the matching monitor when `start.sh` asks.
- **Junk lines in the transcript** (e.g. "Thanks for watching!") → whisper
  hallucinates on music. If you play background music during sessions, keep it
  out of the recorded output (e.g. play it on another device) or just ignore
  those lines — the LLM summary won't care.
- **Transcription too slow** → use a smaller model:
  `MODEL=small ./transcribe.sh sessions/<dir>`.
- **Wrong language in the transcript** → pass `LANG_CODE=it` (or your
  language, or `auto`).
- **Live draft lines look garbled** → normal: the draft uses a small fast
  model. The final `transcript.txt` is made with the big one.
- **No live draft lines appear** → either nobody spoke (silent chunks are
  skipped) or no fast model is installed — get one with `MODEL=base ./install.sh`.
