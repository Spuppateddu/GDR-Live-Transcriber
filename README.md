# GDR Live Transcriber

**Real-time speech-to-text for tabletop RPG ("GDR") sessions on Linux.**

It mixes your **microphone** + your PC's **audio output** (game / voice chat like
Discord) into a single stream, transcribes it **live and offline** with
[whisper.cpp](https://github.com/ggerganov/whisper.cpp), and saves both a `.txt`
transcript and a `.wav` backup recording.

The session language defaults to **Italian** (`it`) — whisper's multilingual
models understand Italian out of the box. You can change it (see Options).

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
1. installs system dependencies (ffmpeg, pulseaudio-utils, SDL2, build tools);
2. downloads and builds whisper.cpp with live-stream support;
3. **detects your CPU/RAM, recommends a model, and lets you choose** which to download.

### Which model?

whisper is **multilingual**, so Italian is supported by all of these. During
install you get a menu with a hardware-based recommendation; here's the guide:

| Model      | Speed  | Accuracy | When to use                                |
|------------|--------|----------|--------------------------------------------|
| `tiny`     | fastest| low      | very weak CPUs / testing                   |
| `base`     | fast   | decent   | 2-core CPUs                                |
| `small`    | good   | good     | **live** on a 4-core CPU (typical pick)    |
| `medium`   | medium | great    | live on 8+ core CPU with 16+ GB RAM        |
| `large-v3` | slow   | best     | NOT for live → final re-transcription of `.wav` |

> ⚠️ Do not use the `.en` models (e.g. `small.en`): those are **English only**.

You can skip the menu and force a model (handy to download a second one):

```bash
MODEL=large-v3 ./install.sh    # also grab large-v3 for the final transcription
```

`start.sh` automatically uses whichever model you installed (if you have several,
it picks the best one suitable for live); you can always override with `MODEL=...`.

---

## 2. Before first use: set your default devices

The script captures the **default microphone** and the **default audio output**.
Open *Settings → Sound* and make sure the correct mic and speakers/headphones
are selected as the defaults.

---

## 3. Start a session (live)

```bash
./start.sh
```

- Text appears on screen as you talk/play.
- Press **Ctrl+C** to stop (the script cleans up the audio mixer automatically).

Files are saved in `sessions/<date_time>/`:

```
sessions/2026-06-28_21-00-00/
├── transcript.txt   ← live transcript
└── recording.wav    ← audio backup
```

### Options

```bash
LANG_CODE=en ./start.sh        # change language (default: it = Italian)
MODEL=medium ./start.sh        # use a specific model for the live run
```

---

## 4. (Optional) High-quality final transcription

After a session you can re-transcribe the recording with the most accurate model
to get a cleaner text:

```bash
MODEL=large-v3 ./transcribe.sh sessions/2026-06-28_21-00-00/recording.wav
```

It creates a `recording.txt` next to the audio file.

---

## How it works (in short)

`start.sh` uses PipeWire/PulseAudio to create a *null sink* called `gdr_mix` that
acts as a mixer: it routes both the **output monitor** and the **microphone**
into it. Its `gdr_mix.monitor` therefore carries mic + audio together, and is fed
to whisper.cpp (live) and to `parec` (the `.wav` backup). On exit, the temporary
audio modules are removed automatically.

---

## Troubleshooting

- **"whisper-stream not found"** → run `./install.sh` first.
- **Game audio not transcribed** → check that the default output in
  *Settings → Sound* is the one you're actually using.
- **Choppy / laggy live transcription** → use a smaller model
  (`MODEL=small ./start.sh` or `MODEL=base`) and rely on `transcribe.sh` for the
  high-quality final pass.
- **No sound in the `.wav`** → verify `gdr_mix` is active during the session
  (`pactl list short sinks | grep gdr_mix`).
- **Wrong language in the transcript** → pass `LANG_CODE=it` (or your language).
