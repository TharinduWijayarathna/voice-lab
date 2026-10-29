<p align="center">
  <img src="docs/icon-256.png" width="128" height="128" alt="VoiceLab icon">
</p>

<h1 align="center">VoiceLab</h1>

<p align="center"><b>Natural voice-overs, made on your Mac.</b><br>
Private, offline, and every clip is yours to keep.</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-E0242F?logo=apple&logoColor=white">
  <img alt="SwiftUI with Liquid Glass" src="https://img.shields.io/badge/SwiftUI-Liquid%20Glass-E0242F?logo=swift&logoColor=white">
  <img alt="Kokoro-82M, Apache-2.0" src="https://img.shields.io/badge/voice-Kokoro--82M-E0242F">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="900" alt="VoiceLab: the voice list on the left, the script and clips in the middle, and the sound settings on the right, on red Liquid Glass">
  </picture>
</p>

A small Mac app for making voice-over clips with the Kokoro voice model. Everything runs on your Mac: no account, no internet once it's installed, and the clips are yours to use (Kokoro-82M is Apache-2.0).

The window is native SwiftUI with Liquid Glass: the voice list in the sidebar, then the script, your clips and the sound settings on glass panels over a soft red glow. It follows your Mac's light or dark appearance.

## Screenshots

| Light | Dark |
|---|---|
| <img src="docs/screenshot-light.png" alt="VoiceLab in light mode"> | <img src="docs/screenshot-dark.png" alt="VoiceLab in dark mode"> |

## What you need

- macOS 26 (Tahoe) or later
- Xcode 26, installed from the App Store and opened once (VoiceLab is built from source on your Mac)

## Install

Double-click **`install.command`**. If macOS says it can't be opened, right-click it, choose **Open**, then **Open** again.

It takes a few minutes the first time:
1. Checks for macOS 26 and Xcode's Swift.
2. Finds Python 3.10 to 3.13 for the voice engine. If you don't have one, it offers to install a private copy (with uv).
3. Installs the voice engine's packages, about 150 MB.
4. Downloads the voice model once, about 355 MB.
5. Builds the app and puts **VoiceLab** in your Applications folder, then opens it.

Run `install.command` again any time to update the app after changing its code here.

## Using it

- **Voices** (sidebar): click a name to use it. Hover and press play to hear a short sample. The "Most natural" voices are the model's cleanest. Search with the field at the top.
- **Script**: type or paste, then press **Make clip** (⌘↵).
  - **A clip per line** makes a separate file for every line. This is handy for an ad script.
- **Clips**: every clip is saved as a WAV file in `Documents › VoiceLab`, numbered in the order you made them.
  - Click the waveform to jump to that point. ⌘L plays the latest clip.
  - Click a title to rename the clip (the file is renamed too).
  - Hover over a clip for its buttons: **Use again** (↩) brings its script and settings back into the editor, **Show in Finder** (folder), and **Delete** (bin) moves the file to the Bin. Right-click a clip for the same things.
- **Sound** (the panel on the right):
  - **Speed** and **Pause after each sentence** change how it's read. The round ↺ button next to a value puts it back to normal.
  - **Blend with another voice** mixes two voices into a new one. For example, Heart with 30% Emma.
  - **Pronunciation** fixes words the voice says wrong. Write the word as it sounds (`ee-kwate`), or give the exact sounds between slashes (`/kəkˈɔːɹoʊ/`). The play button tries it out.

## Where things live

| What | Where |
|---|---|
| Your clips | `~/Documents/VoiceLab` (change it in the app) |
| The app | `~/Applications/VoiceLab.app` |
| Model, Python packages, settings, a log | `~/Library/Application Support/VoiceLab` (about 500 MB) |

To remove it completely, delete the app and that Application Support folder.

## How it's made

- `mac/`: the app, a Swift package (SwiftUI, macOS 26). Open the folder in Xcode 26 to work on it.
  - `Engine.swift` starts the voice engine and talks to it; `Studio.swift` holds what the window shows and does; the rest are the views.
- `engine/`: the voice engine in Python, which the app starts in the background.
  - `engine.py`: the Kokoro model, the voice list, pronunciations and the clips.
  - `server.py`: a private server for the app (this Mac only, `127.0.0.1`). It quits when the app quits.
- `icon/`: the app icon. `docs/`: the README icon and screenshots.

To run it from Xcode or Terminal without installing: run `install.command` once (for the Python engine and the model), then `cd mac && swift run`. The app finds `engine/server.py` next to it.
