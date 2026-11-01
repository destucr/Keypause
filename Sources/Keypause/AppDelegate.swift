import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = CleaningSession()
    private lazy var overlay = OverlayController(session: session)
    private var statusItem: NSStatusItem!

    private let durations: [(label: String, seconds: TimeInterval)] = [
        ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120),
        ("5 minutes", 300), ("10 minutes", 600),
    ]
    private var selectedDuration: TimeInterval {
        get { UserDefaults.standard.object(forKey: "duration") as? TimeInterval ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: "duration") }
    }

    private var dimScreen: Bool {
        get { UserDefaults.standard.bool(forKey: "dimScreen") }
        set { UserDefaults.standard.set(newValue, forKey: "dimScreen") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        session.onChange = { [weak self] in
            guard let self else { return }
            self.updateIcon()
            if self.session.isActive { self.overlay.show(dimScreen: self.dimScreen) } else { self.overlay.hide() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { session.stop() }

    private func updateIcon() {
        let name = session.isActive ? "keyboard.fill" : "keyboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Keypause")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Menu (rebuilt each time it opens so state is always fresh)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if session.isActive {
            menu.addItem(item("Unlock Keyboard", #selector(stopCleaning)))
        } else {
            let start = item("Start Cleaning", #selector(startCleaning))
            menu.addItem(start)
        }

        let durationItem = NSMenuItem(title: "Duration", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for d in durations {
            let i = item(d.label, #selector(pickDuration(_:)))
            i.representedObject = d.seconds
            i.state = d.seconds == selectedDuration ? .on : .off
            sub.addItem(i)
        }
        durationItem.submenu = sub
        durationItem.isEnabled = !session.isActive
        menu.addItem(durationItem)

        menu.addItem(.separator())
        let dim = item("Dim Screen While Locked", #selector(toggleDim))
        dim.state = dimScreen ? .on : .off
        dim.isEnabled = !session.isActive
        menu.addItem(dim)
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Keypause", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    // MARK: Actions

    @objc private func startCleaning() {
        if session.start(duration: selectedDuration) == .needsPermission {
            KeyboardLock.requestPermission()
            let alert = NSAlert()
            alert.messageText = "Keypause needs Accessibility access"
            alert.informativeText = "To disable the keyboard, allow Keypause in System Settings → Privacy & Security → Accessibility, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func stopCleaning() { session.stop() }

    @objc private func pickDuration(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? TimeInterval { selectedDuration = s }
    }

    @objc private func toggleDim() { dimScreen.toggle() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
    }
}
