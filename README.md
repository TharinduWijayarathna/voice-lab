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

A small Mac app for making voice-over clips with the Kokoro voice model. Everything runs on your Mac: no account, no internet once it's installed, and the clips are yours to use (Kokoro-82M is Apache-2.0).

The window is native SwiftUI with Liquid Glass: a voice list in the sidebar, the script and your clips on glass panels over a soft red glow, and the sound settings in the inspector. It follows your Mac's light or dark appearance.

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
  - **Use again** brings that clip's script and settings back into the editor.
  - **Delete** moves the file to the Bin. Right-click a clip for all of these.
- **Sound** (inspector, toggle it from the toolbar):
  - **Speed** and **Pause after each sentence** change how it's read. **Normal** resets the speed.
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
- `icon/`: the app icon. `docs/`: the README icon.

To run it from Xcode or Terminal without installing: run `install.command` once (for the Python engine and the model), then `cd mac && swift run`. The app finds `engine/server.py` next to it.
