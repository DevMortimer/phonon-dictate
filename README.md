# Phonon Dictate

A macOS menu-bar dictation app that runs [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2) on your Mac.

- Press **⌥Space** to start recording. An overlay at the bottom of the screen shows a live waveform.
- Press **⌥Space** again to stop. The text goes to the clipboard and to the history. **Esc** cancels.
- The model loads in a fresh process when recording starts (so it loads while you speak) and unloads when that process exits after the transcription.
- Phonon-2 is the only supported model.

## Requirements

- Apple silicon Mac, macOS 14 or later
- [uv](https://docs.astral.sh/uv/) (`brew install uv`). The app uses it on first launch to make its Python environment.
- Xcode command line tools to build

## Build and run

```sh
./scripts/build-app.sh            # builds "build/Phonon Dictate.app"
./scripts/build-app.sh --install  # also copies it to ~/Applications
open "build/Phonon Dictate.app"
```

On first launch the app installs the pinned Python packages (`python/requirements.txt`) into its own environment and downloads Phonon-2 (164 MB). The menu-bar item shows the progress. macOS asks for microphone access the first time you dictate.

## Menu bar and settings

The menu-bar item shows the status, recent transcripts (click to copy), the history window, and the recordings folder. **Settings…** has:

- Shortcut: click the button and press a new key combination.
- Keep recordings: 1, 7, 30, 90, or 365 days, or forever (default 7 days).
- Keep history: 1, 7, 30, 90, or 365 days, or forever (default 30 days).
- Launch at login.

## Files

Everything is in `~/Library/Application Support/Phonon Dictate/`:

| Path | Content |
| --- | --- |
| `recordings/*.wav` | 16 kHz mono recordings, deleted after the retention period |
| `history.json` | Transcripts, deleted after the retention period |
| `python/` | The Python environment |
| `setup.log`, `worker.log` | Logs for setup and transcription |

The model files are in `~/.cache/fermion/`.

## How it works

- `Sources/PhononDictate/` is the Swift app: Carbon global hotkey, `AVAudioEngine` recorder, overlay panel, menu-bar item, settings, and history.
- `python/worker.py` is a one-shot worker. It loads Phonon-2 through the `fermion-research` package, reads one WAV path from stdin, prints one JSON line, and exits.

## Licences

Phonon-2 weights: CC-BY-4.0, by FermionResearch, based on NVIDIA parakeet-tdt-0.6b-v3. The `fermion-research` package: Apache 2.0.
