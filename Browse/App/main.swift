import AppKit

final class BrowserApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        // Intercept ⌘⌥C before any window processes it
        if event.type == .keyDown,
           event.modifierFlags.intersection([.command, .option, .shift, .control]) == [.command, .option],
           event.keyCode == 8 {
            if let delegate = self.delegate as? AppDelegate {
                delegate.toggleInspector(nil)
                return
            }
        }
        super.sendEvent(event)
    }
}

// Register our custom subclass before NSApplication.shared is called
let app = BrowserApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
