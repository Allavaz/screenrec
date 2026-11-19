# AGENTS.md

Menu-bar-only macOS 14 screen recorder (Swift 5.9, SwiftPM). One executable target in `Sources/ScreenRec`, zero dependencies; no tests, CI, lint, or formatter config — the only checks are a compile and a manual capture run.

## Build & run

```bash
./build.sh                 # swift build -c release, rebuild build/ScreenRec.app, ad-hoc codesign
open build/ScreenRec.app
swift build -c release     # compile check only
```

- **Test capture through the `.app`, never the raw binary.** Running `.build/release/ScreenRec` directly gets Screen Recording permission granted to the terminal; the bundle is what TCC identifies. `build.sh` also `rm -rf`s the bundle each run, so edits to the built `Info.plist` are lost.
- `Info.plist` lives only in a heredoc inside `build.sh`. `LSUIElement=true` there is what keeps the app dockless. The bundle ID `com.david.screenrec` plus the ad-hoc signature is the TCC identity — changing either forces a fresh permission grant.
- No test target, so `swift test` runs nothing. Verify manually: build, left-click start, record a few seconds, left-click stop, confirm the MP4 in `~/Movies` has an audio track.
- If capture fails right after granting permission, quit and relaunch — macOS often doesn't apply a new TCC grant to a running process.

## Architecture gotchas

- `main.swift` is **top-level code**, not `@main`; adding an `@main` type breaks the build. Activation policy is `.accessory` (no dock icon, no windows).
- No class is `@MainActor`-annotated. `StatusBarController` state must be mutated on main (existing code wraps async work in `Task { @MainActor in … }`); capture callbacks fire on `Recorder.sampleQueue`, a serial background queue — don't touch UI or recorder state from there.
- **A/V sync is a contract:** `Recorder.retime` rebases every sample against the first received PTS and `MovieWriter.begin` starts the session at `.zero`. Change one without the other and recordings desync or fail.
- **Dimensions are pixels:** `SCStreamConfiguration.width/height` take `display.width × backingScaleFactor` (scale falls back to `2` when no `NSScreen` matches the display ID). `Recorder.pixels(for:)` feeds the same values to `MovieWriter`; if they disagree, AVAssetWriter rejects the video.
- **Audio settings are a matched pair:** 48 kHz / 2 channels in `SCStreamConfiguration` must match `MovieWriter`'s AAC output settings (48 kHz, 2 ch, 192 kbps).
- `MovieWriter.append*` deliberately drops samples when `isReadyForMoreMediaData` is false — correct for realtime capture. Don't add blocking waits or buffers.
- The status item has **no permanent menu**: left click toggles recording, right click opens the menu. `openMenu()` attaches `menu` only around `performClick`; setting `statusItem.menu` permanently kills left-click start/stop.
- Top-level menu sets `autoenablesItems = false`, so every item needs an explicit `isEnabled`/`target` or it silently does nothing. While recording, the toggle item's title is overwritten with the elapsed time every second.
- `Settings.displayID == 0` is the sentinel for "first available display", not a real ID. Settings persist via `UserDefaults` (`saveFolderURL`, `displayID`) as a plain path URL — no security-scoped bookmarks; the app is unsandboxed and has no entitlements file.
- Output defaults to `~/Movies` as `Recording yyyy-MM-dd HH-mm-ss.mp4`, with ` 2`, ` 3`, … on collision. `.microphone` samples are intentionally ignored (system audio only).
