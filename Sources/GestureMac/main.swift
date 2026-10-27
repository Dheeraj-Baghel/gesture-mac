import AppKit

// The app starts without camera capture or enabled synthetic input. Permissions
// and control are separate, user-triggered steps in the native window.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
