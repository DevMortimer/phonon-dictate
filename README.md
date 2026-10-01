<div align="center">

# Phonon Dictate

**Press ⌥Space, talk, press ⌥Space again. The text is on your clipboard.**

On-device dictation for the Mac, powered by [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2).

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Apple silicon](https://img.shields.io/badge/Apple%20silicon-required-555555?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Package.swift)
[![Model: Phonon-2](https://img.shields.io/badge/%F0%9F%A4%97%20model-Phonon--2-FFD21E)](https://huggingface.co/FermionResearch/Phonon-2)
[![Runs on device](https://img.shields.io/badge/audio-never%20leaves%20your%20Mac-2EA44F)](#privacy)
[![Last commit](https://img.shields.io/github/last-commit/DevMortimer/phonon-dictate)](https://github.com/DevMortimer/phonon-dictate/commits/main)

</div>

---

## Features

- **One shortcut.** ⌥Space starts and stops recording. Esc cancels. You can change the shortcut in Settings.
- **Live waveform.** A small overlay at the bottom of the screen moves with your voice while you record.
- **Clipboard and history.** Every transcript goes to the clipboard and to a searchable history window.
- **Recordings kept.** Each recording is saved as a WAV file, so you can listen to it again.
- **Retention periods.** Recordings and history are deleted after a period you choose (defaults: 7 days and 30 days).
- **Model only in memory while it works.** The model loads when you start recording, so it is ready when you stop. It unloads when the transcript is done. Nothing stays in memory between dictations.
- **One model.** Phonon-2: 164 MB, 5.21 % average word error rate on the Open ASR Leaderboard English sets.

## Requirements

- A Mac with Apple silicon and macOS 14 or later
- [uv](https://docs.astral.sh/uv/): `brew install uv`
- Xcode or the Xcode Command Line Tools, to build

## Quick start

```sh
git clone https://github.com/DevMortimer/phonon-dictate.git
cd phonon-dictate
./scripts/build-app.sh --install    # builds the app and copies it to ~/Applications
open ~/Applications/"Phonon Dictate.app"
```

### First launch

The first launch sets up the speech engine. You do not have to do anything:

1. The app makes its own Python environment with uv.
2. It installs the pinned packages from `python/requirements.txt` (about 1 GB, mostly PyTorch and MLX).
3. It downloads Phonon-2 (164 MB), checks the download, and compiles the GPU shaders.

The menu-bar item shows each step. When the menu says **Press ⌥Space to dictate**, the app is ready. The first time you dictate, macOS asks for microphone access.

## Usage

| Action | How |
| --- | --- |
| Start recording | ⌥Space |
| Stop and transcribe | ⌥Space |
| Cancel | Esc |
| Copy a recent transcript | Menu-bar item → Recent |
| Search all transcripts | Menu-bar item → History… |
| Listen to a recording | History → Show Recording |

## Settings

Open **Settings…** from the menu-bar item.

| Setting | Choices | Default |
| --- | --- | --- |
| Shortcut | Any key with ⌃ ⌥ ⇧ or ⌘, or a function key | ⌥Space |
| Keep recordings | 1, 7, 30, 90, 365 days, or forever | 7 days |
| Keep history | 1, 7, 30, 90, 365 days, or forever | 30 days |
| Launch at login | On or off | Off |

## Privacy

All recording and transcription happen on your Mac. The app connects to the internet only during the first launch, to download the Python packages from PyPI and the model from Hugging Face. After setup, the worker runs with `HF_HUB_OFFLINE=1`.

## Files

Everything is in `~/Library/Application Support/Phonon Dictate/`:

| Path | Content |
| --- | --- |
| `recordings/*.wav` | 16 kHz mono recordings |
| `history.json` | Transcripts |
| `python/` | The Python environment |
| `setup.log` | Log of the first-launch setup |
| `worker.log` | Log of each transcription |

The model files are in `~/.cache/fermion/`.

## How it works

```
⌥Space ──► Recorder (AVAudioEngine, 16 kHz WAV) ──► overlay waveform
   │
   └─────► worker.py starts and loads Phonon-2 while you speak
⌥Space ──► WAV path sent to the worker ──► text ──► clipboard + history
                                            └──► worker exits, model unloads
```

- `Sources/PhononDictate/`: the Swift app. Carbon global hotkey, recorder, overlay panel, menu-bar item, settings, and history.
- `python/worker.py`: a one-shot worker. It loads Phonon-2 through the [`fermion-research`](https://pypi.org/project/fermion-research/) package, reads one WAV path from stdin, prints one JSON line, and exits.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| The menu says the shortcut is used by another app | Choose a different shortcut in Settings. |
| The menu says "Setup failed" | Read `setup.log`. Make sure uv is installed, then quit and open the app again. |
| No microphone prompt appears | Run `tccutil reset Microphone com.devmortimer.PhononDictate`, then dictate again. |
| "Transcription failed" | Read `worker.log`. |

## Uninstall

```sh
rm -rf ~/Applications/"Phonon Dictate.app" ~/Library/Application\ Support/Phonon\ Dictate ~/.cache/fermion
defaults delete com.devmortimer.PhononDictate
```

## Credits

- [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2) by FermionResearch. Weights: CC-BY-4.0. Based on [NVIDIA parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).
- [`fermion-research`](https://github.com/fermionresearch/phonon): Apache 2.0.
