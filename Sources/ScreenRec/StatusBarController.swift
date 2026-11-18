import AppKit
import ScreenCaptureKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let recorder = Recorder()

    private var recordingMenuItem: NSMenuItem?
    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?
    private var displays: [SCDisplay] = []
    private var displaysRequested = false

    func start() {
        menu.delegate = self
        menu.autoenablesItems = false
        updateIcon(recording: false)
        rebuildMenu()

        // Handle clicks ourselves: left click starts/stops recording,
        // right click opens the menu.
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Click handling

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            toggleRecording()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            openMenu()
        } else {
            toggleRecording()
        }
    }

    private func openMenu() {
        // Briefly attaching the menu makes performClick() pop it up
        // anchored under the status item, like a normal menu bar menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()
        let recording = recorder.isRecording

        let toggle = NSMenuItem(
            title: recording ? "Stop Recording" : "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = true
        menu.addItem(toggle)
        recordingMenuItem = toggle

        menu.addItem(.separator())

        let folder = NSMenuItem(
            title: "Save Folder: \(Settings.saveFolderURL.lastPathComponent) ▸",
            action: nil,
            keyEquivalent: ""
        )
        let folderMenu = NSMenu()
        folderMenu.addItem(withTitle: "Open in Finder", action: #selector(openFolder), keyEquivalent: "").target = self
        folderMenu.addItem(withTitle: "Choose Folder…", action: #selector(chooseFolder), keyEquivalent: "").target = self
        folder.submenu = folderMenu
        folder.isEnabled = !recording
        menu.addItem(folder)

        let display = NSMenuItem(title: "Display ▸", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        if displays.isEmpty {
            let placeholder = NSMenuItem(title: "Loading displays…", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            displayMenu.addItem(placeholder)
        } else {
            for (index, candidate) in displays.enumerated() {
                let item = NSMenuItem(
                    title: "Display \(index + 1)  (\(candidate.width)×\(candidate.height))",
                    action: #selector(selectDisplay(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = Int(candidate.displayID)
                let isSelected = Int(candidate.displayID) == Settings.displayID
                    || (Settings.displayID == 0 && index == 0)
                item.state = isSelected ? .on : .off
                displayMenu.addItem(item)
            }
        }
        display.submenu = displayMenu
        display.isEnabled = !recording
        menu.addItem(display)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ScreenRec", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)

        if recording {
            updateElapsedTitle()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        requestDisplaysIfNeeded()
        rebuildMenu()
    }

    private func requestDisplaysIfNeeded() {
        guard !displaysRequested else { return }
        displaysRequested = true
        Task { @MainActor in
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.displays = content?.displays ?? []
            self.rebuildMenu()
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !recorder.isRecording else { return }

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }

        let folder = Settings.saveFolderURL
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            showError("Couldn't create save folder: \(error.localizedDescription)")
            return
        }
        let outputURL = uniqueOutputURL(in: folder)

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                self.displays = content.displays

                let target: SCDisplay?
                if Settings.displayID == 0 {
                    target = content.displays.first
                } else {
                    target = content.displays.first(where: { Int($0.displayID) == Settings.displayID })
                }
                guard let display = target else { throw RecordingError.noDisplay }

                try await self.recorder.start(display: display, outputURL: outputURL)
                self.recordingStartDate = Date()
                self.updateIcon(recording: true)
                self.startTimer()
                self.rebuildMenu()
            } catch {
                self.showError("Couldn't start recording: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecording() {
        guard recorder.isRecording else { return }
        stopTimer()
        Task { @MainActor in
            do {
                _ = try await self.recorder.stop()
            } catch {
                self.showError("Couldn't finish recording: \(error.localizedDescription)")
            }
            self.recordingStartDate = nil
            self.updateIcon(recording: false)
            self.rebuildMenu()
        }
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int else { return }
        Settings.displayID = id
        rebuildMenu()
    }

    @objc private func openFolder() {
        let folder = Settings.saveFolderURL
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(folder)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Settings.saveFolderURL
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                Settings.saveFolderURL = url
                self?.rebuildMenu()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func uniqueOutputURL(in folder: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let base = "Recording " + formatter.string(from: Date())
        var url = folder.appendingPathComponent(base + ".mp4")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(counter).mp4")
            counter += 1
        }
        return url
    }

    private func startTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateElapsedTitle()
        }
    }

    private func stopTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsedTitle() {
        guard let start = recordingStartDate, let item = recordingMenuItem else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        item.title = "Stop Recording  ·  " + elapsedText(seconds)
    }

    private func elapsedText(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func updateIcon(recording: Bool) {
        guard let button = statusItem.button else { return }
        // Template images let macOS color the icon to match the menu bar
        // (light/dark mode, highlight on open), like every native menu bar icon.
        let image = NSImage(
            systemSymbolName: recording ? "stop.circle.fill" : "record.circle",
            accessibilityDescription: "ScreenRec"
        )
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = nil
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = "ScreenRec needs permission to capture your display. Enable it in System Settings → Privacy & Security → Screen Recording, then start recording again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "ScreenRec"
        alert.informativeText = message
        alert.runModal()
    }
}
