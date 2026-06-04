import AppKit

let application = NSApplication.shared
let delegate = MainApplication()

application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
