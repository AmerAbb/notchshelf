import AppKit

// A plain AppKit entry point: the app is a borderless panel at the notch plus
// a menu bar item, with no windows of its own to describe in a SwiftUI Scene.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
