import AppKit

// Menu-bar-only app: no dock icon, no windows.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = StatusBarController()
controller.start()

app.run()
