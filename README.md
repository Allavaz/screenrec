# ScreenRec

A minimal macOS screen recorder for the menu bar that captures **system audio** — the thing the built-in screen recorder can't do.

- Entire-screen capture at 60 fps (Retina-aware) with the system's audio output, muxed into an MP4 (H.264 + AAC)
- Menu bar icon: **left click** to start/stop recording, **right click** for the menu
- Elapsed-time display while recording
- Configurable save folder (default `~/Drawer`) and display picker for multi-monitor setups — both persisted between runs
- No dock icon, no windows: lives entirely in the menu bar

## Requirements

- macOS 14.0+
- Xcode toolchain (Swift 5.9) for building

## Build & run

```bash
./build.sh
open build/ScreenRec.app
```

`build.sh` compiles in release mode and wraps the binary in a minimal ad-hoc–signed `ScreenRec.app` bundle — the bundle is what makes macOS grant Screen Recording permission to the app itself rather than to Terminal.

## First launch

Screen Recording permission is required (one time): when you click **Start Recording**, macOS will prompt, or the app will offer to open **System Settings → Privacy & Security → Screen Recording**. Enable ScreenRec, then start recording again.

## Usage

| Action | Result |
| --- | --- |
| Left click on icon | Start / stop recording |
| Right click on icon | Open menu |
| Stop Recording | Finalizes the MP4 in the save folder (no window pops up) |
| Save Folder ▸ Open in Finder | Opens the current save folder |
| Save Folder ▸ Choose Folder… | Pick a new destination (remembered) |
| Display ▸ | Choose which monitor to record (remembered) |

Recordings are auto-named like `Recording 2026-11-18 15-04-22.mp4`.

## How it works

- **ScreenCaptureKit** provides a single stream with the display's frames and the system's audio output (`capturesAudio`), with the recorder's own audio excluded
- Samples are retimed relative to the first received sample so the movie starts at 0:00
- **AVAssetWriter** encodes video to H.264 and audio to AAC and writes the MP4 incrementally, so stopping is fast
- Settings (save folder, display ID) live in `UserDefaults`

## Project layout

```
Sources/ScreenRec/
├── main.swift                 # menu-bar-only app lifecycle
├── StatusBarController.swift  # icon, click handling, menu, timer
├── Recorder.swift             # SCStream capture + sample retiming
├── MovieWriter.swift          # AVAssetWriter (H.264 video + AAC audio)
└── Settings.swift             # persisted folder & display choice
```

## Ideas for later

- Microphone mixing toggle
- Window / region capture
- Pause & resume
- Custom bitrate / codec options
