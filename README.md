# GDR Live Transcriber

Trascrizione vocale **in tempo reale** per le tue sessioni di gioco di ruolo (GDR) su Linux.

Lo strumento mixa il tuo **microfono** + l'**audio in uscita** del PC (gioco / chat
vocale tipo Discord) in un unico flusso, lo trascrive **dal vivo e offline** con
[whisper.cpp](https://github.com/ggerganov/whisper.cpp), e salva sia la
trascrizione in `.txt` sia una registrazione audio `.wav` di backup.

> Tutto in locale: dopo l'installazione **non serve internet né alcun account**.

---

## Requisiti

- **Ubuntu 24.04** (o derivata) con **PipeWire** (predefinito su Ubuntu 24.04).
- Funziona su **CPU** (nessuna GPU NVIDIA richiesta).
- ~2 GB di spazio per modello + compilazione.

---

## 1. Installazione (una volta sola)

```bash
git clone git@github.com:Spuppateddu/GDR-Live-Transcriber.git
cd GDR-Live-Transcriber
./install.sh
```

`install.sh` fa tutto:
1. installa le dipendenze di sistema (ffmpeg, pulseaudio-utils, SDL2, strumenti di build);
2. scarica e compila whisper.cpp con il supporto al live-stream;
3. **rileva la tua CPU/RAM, consiglia un modello e ti fa scegliere** quale scaricare.

### Quale modello?

whisper è **multilingue**, quindi l'italiano è già supportato. Durante
l'installazione lo script ti mostra un menu e suggerisce il modello in base
all'hardware; questa è la guida:

| Modello    | Velocità | Precisione | Quando usarlo                              |
|------------|----------|------------|--------------------------------------------|
| `tiny`     | massima  | bassa      | CPU molto deboli / test                    |
| `base`     | alta     | discreta   | CPU 2 core                                 |
| `small`    | buona    | buona      | **live** su CPU 4 core (consigliato tipico)|
| `medium`   | media    | ottima     | live su CPU 8+ core e 16+ GB RAM           |
| `large-v3` | lenta    | massima    | NON per il live → ri-trascrizione del `.wav` |

> ⚠️ Non usare i modelli che finiscono in `.en` (es. `small.en`): sono **solo inglese**.

Puoi saltare il menu e forzare un modello (utile per rieseguire o per scaricarne
un secondo):

```bash
MODEL=large-v3 ./install.sh    # scarica anche large-v3 per la trascrizione finale
```

`start.sh` userà automaticamente il modello che hai installato (se ne hai più di
uno, sceglie il migliore adatto al live); puoi sempre forzarlo con `MODEL=...`.

---

## 2. Prima dell'uso: imposta i dispositivi predefiniti

Lo script cattura il **microfono predefinito** e l'**uscita audio predefinita**.
Apri *Impostazioni → Audio* e assicurati che siano selezionati il microfono e
le casse/cuffie giusti come predefiniti.

---

## 3. Avviare una sessione (live)

```bash
./start.sh
```

- Il testo compare a schermo mentre parli/giochi.
- Premi **Ctrl+C** per fermare (lo script ripulisce da solo il mixer audio).

I file vengono salvati in `sessions/<data_ora>/`:

```
sessions/2026-06-28_21-00-00/
├── transcript.txt   ← trascrizione live
└── recording.wav    ← registrazione audio di backup
```

### Opzioni

```bash
LANG_CODE=en ./start.sh        # cambia lingua (default: it)
MODEL=medium ./start.sh        # usa un altro modello per il live
```

---

## 4. (Opzionale) Trascrizione finale di alta qualità

A fine sessione puoi ri-trascrivere la registrazione con il modello più preciso
per avere un testo migliore:

```bash
MODEL=large-v3 ./transcribe.sh sessions/2026-06-28_21-00-00/recording.wav
```

Crea un `recording.txt` accanto al file audio.

---

## Come funziona (in breve)

`start.sh` crea con PipeWire/PulseAudio un *null sink* chiamato `gdr_mix` che fa
da mixer: ci instrada dentro il **monitor dell'uscita audio** e il
**microfono**. Il suo `gdr_mix.monitor` contiene quindi mic + audio insieme, e
viene dato in pasto a whisper.cpp (live) e a `parec` (backup `.wav`).
All'uscita, i moduli audio temporanei vengono rimossi automaticamente.

---

## Risoluzione problemi

- **"whisper-stream not found"** → esegui prima `./install.sh`.
- **Non trascrive l'audio del gioco** → controlla che l'uscita predefinita in
  *Impostazioni → Audio* sia quella che stai effettivamente usando.
- **Va a scatti / in ritardo nel live** → usa un modello più piccolo
  (`MODEL=small ./start.sh` o `MODEL=base`) e affidati alla ri-trascrizione
  finale con `transcribe.sh` per la qualità.
- **Non si sente nel `.wav`** → verifica che `gdr_mix` sia attivo durante la
  sessione (`pactl list short sinks | grep gdr_mix`).
