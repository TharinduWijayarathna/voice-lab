<p align="center">
  <img src="docs/icon-256.png" width="128" height="128" alt="VoiceLab icon">
</p>

<h1 align="center">VoiceLab</h1>

<p align="center"><b>Natural voice-overs, made on your Mac.</b><br>
Private, offline, and every clip is yours to keep.</p>

<p align="center">
  <img alt="macOS 11+" src="https://img.shields.io/badge/macOS-11%2B-E0242F?logo=apple&logoColor=white">
  <img alt="Python 3.10 to 3.13" src="https://img.shields.io/badge/Python-3.10%E2%80%933.13-E0242F?logo=python&logoColor=white">
  <img alt="Kokoro-82M, Apache-2.0" src="https://img.shields.io/badge/voice-Kokoro--82M-E0242F">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="900" alt="VoiceLab: voices on the left, the script and clips in the middle, sound settings on the right">
  </picture>
</p>

A small Mac app for making voice-over clips with the Kokoro voice model. Everything runs on your Mac: no account, no internet once it's installed, and the clips are yours to use (Kokoro-82M is Apache-2.0).

## Screenshots

| Light | Dark |
|---|---|
| <img src="docs/screenshot-light.png" alt="VoiceLab in light mode"> | <img src="docs/screenshot-dark.png" alt="VoiceLab in dark mode"> |

The window follows your Mac's light or dark appearance: frosted glass panels over a soft red glow.

## Install

Double-click **`install.command`**. If macOS says it can't be opened, right-click it, choose **Open**, then **Open** again.

It takes a few minutes the first time:
1. Finds Python 3.10 to 3.13. If you don't have one, it offers to install a private copy (with uv).
2. Installs the packages: the voice model's runtime and the app window, about 200 MB.
3. Downloads the voice model once, about 355 MB.
4. Puts **VoiceLab** in your Applications folder and opens it.

Run `install.command` again any time to update the app after changing its code here.

## Using it

- **Voices** (left): click a name to use it. The play button beside it plays a short sample. The "Most natural" voices are the model's cleanest.
- **Script** (middle): type or paste, then press **Make clip** (⌘↵).
  - **A clip per line** makes a separate file for every line, numbered in the margin. This is handy for an ad script.
- **Clips**: every clip is saved as a WAV file in `Documents › VoiceLab`, numbered in the order you made them.
  - Click the waveform to jump to that point.
  - Click a title to rename the clip (the file is renamed too).
  - **Use again** brings that clip's script and settings back into the editor.
  - **Delete** moves the file to the Bin.
- **Speed**, **Pause after each sentence**: change how it's read. Double-click the speed slider to reset it to normal.
- **Blend with another voice**: mixes two voices into a new one. For example, Heart with 30% Emma.
- **Pronunciation**: fixes words the voice says wrong. Write the word as it sounds (`ee-kwate`), or give the exact sounds between slashes (`/kəkˈɔːɹoʊ/`). The play button tries it out.

## Where things live

| What | Where |
|---|---|
| Your clips | `~/Documents/VoiceLab` (change it in the app) |
| The app | `~/Applications/VoiceLab.app` |
| Model, Python packages, settings, a log | `~/Library/Application Support/VoiceLab` (about 550 MB) |

To remove it completely, delete the app and that Application Support folder.

## How it's made

- `app.py`: a private web server (this Mac only, `127.0.0.1`), shown in a native window by pywebview.
- `engine.py`: the voice model, the voice list, pronunciations and the clips.
- `ui/`: the interface (HTML, CSS, JS). Fonts: Instrument Sans and Source Serif 4 (SIL Open Font License).
- `icon/`: the app icon.
- `docs/`: the README icon and screenshots.

To run it without building the app: `~/Library/Application\ Support/VoiceLab/venv/bin/python app.py`. Add `--browser` to open it in your browser instead of a window.
