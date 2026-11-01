import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = CleaningSession()
    private lazy var overlay = OverlayController(session: session)
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var previewWindow: NSWindow?
    private let updates = UpdateChecker()

    private var autoCheckUpdates: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdateCheck") }
    }
    private lazy var welcome = WelcomeWindowController { [weak self] in self?.startCleaning() }

    private let durations: [(label: String, seconds: TimeInterval)] = [
        ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120),
        ("5 minutes", 300), ("10 minutes", 600),
    ]
    private var selectedDuration: TimeInterval {
        get { min(max(UserDefaults.standard.object(forKey: "duration") as? TimeInterval ?? 60, 5), 3600) }
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

        // ⌃⌥⌘K starts cleaning from anywhere. (Unlock is by button/timer: the lock swallows keys.)
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_K),
                              modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.startCleaning()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session.isActive else { return }
                self.overlay.show(dimScreen: self.dimScreen)
            }
        }

        session.onChange = { [weak self] in
            guard let self else { return }
            self.updateIcon()
            if self.session.isActive { self.overlay.show(dimScreen: self.dimScreen) }
            else if self.session.justFinished { self.overlay.celebrate() }
            else { self.overlay.hide() }
        }

        // A quiet update check at most once a day. It never pops a dialog; the menu just gains an "Update available" item.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.autoCheckUpdates else { return }
            let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 24 * 3600 { Task { await self.runUpdateCheck(userInitiated: false) } }
        }

        // Show a welcome window when the user opens the app themselves, but stay quiet at login.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if CommandLine.arguments.contains("--kip-preview") {
            previewWindow = makeKipPreviewWindow()
        } else if CommandLine.arguments.contains("--demo-lock") {
            // Dev/QA: start a short lock session immediately (used for README screenshots).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                let arg = CommandLine.arguments.first { $0.hasPrefix("--demo-seconds=") }
                _ = self?.session.start(duration: arg.flatMap { Double($0.dropFirst(15)) } ?? 25)
            }
        } else if !launchedAtLogin {
            welcome.show()
        }
    }

    // Opening Keypause again (Spotlight, Finder) while it's running brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !session.isActive { welcome.show() }
        return true
    }

    // keypause://start?seconds=60  ·  keypause://stop   (try: open "keypause://start")
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "keypause" {
            switch url.host {
            case "start":
                // Any web page or app can open a keypause:// link, so keep it harmless: short cap,
                // and it never changes the user's saved duration.
                let requested = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "seconds" }?.value.flatMap(TimeInterval.init)
                let seconds = min(max(requested ?? selectedDuration, 5), 300)
                beginCleaning(duration: seconds)
            case "stop":
                session.stop()
            case "check":
                checkForUpdates()
            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { session.stop() }

    private func updateIcon() {
        statusItem.button?.image = Self.menuBarIcon(locked: session.isActive)
        statusItem.button?.toolTip = "Keypause"
    }

    /// Keypause's own menu bar glyph: a keycap with a pause symbol.
    /// Outlined when idle; solid with the bars knocked out while the keyboard is locked.
    private static func menuBarIcon(locked: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let cap = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 15, height: 13), xRadius: 4, yRadius: 4)
            let bars = NSBezierPath()
            bars.append(NSBezierPath(roundedRect: NSRect(x: 5.6, y: 5.8, width: 2.3, height: 6.4), xRadius: 0.8, yRadius: 0.8))
            bars.append(NSBezierPath(roundedRect: NSRect(x: 10.1, y: 5.8, width: 2.3, height: 6.4), xRadius: 0.8, yRadius: 0.8))
            NSColor.black.set()
            if locked {
                cap.append(bars)
                cap.windingRule = .evenOdd // bars become holes in the solid key
                cap.fill()
            } else {
                cap.lineWidth = 1.4
                cap.stroke()
                bars.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = locked ? "Keypause (keyboard locked)" : "Keypause"
        return image
    }

    // MARK: Menu (rebuilt each time it opens so state is always fresh)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if session.isActive {
            menu.addItem(item("Unlock Keyboard", #selector(stopCleaning)))
        } else {
            let start = item("Start Cleaning", #selector(startCleaning))
            if hotKey != nil { // show the shortcut next to the item
                start.keyEquivalent = "k"
                start.keyEquivalentModifierMask = [.control, .option, .command]
            }
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
        if let r = updates.available {
            let u = item("Update Available: v\(r.version)…", #selector(showAvailableUpdate))
            menu.addItem(u)
        }
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        let auto = item("Check Automatically", #selector(toggleAutoUpdates))
        auto.state = autoCheckUpdates ? .on : .off
        menu.addItem(auto)
        let ver = NSMenuItem(title: "Keypause \(updates.currentVersion)", action: nil, keyEquivalent: "")
        ver.isEnabled = false
        menu.addItem(ver)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Keypause", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    // MARK: Actions

    @objc private func startCleaning() { beginCleaning(duration: selectedDuration) }

    private func beginCleaning(duration: TimeInterval) {
        // Without permission, bring up the one window that walks through it (no separate alerts, no stacked prompts).
        if session.start(duration: duration) == .needsPermission { welcome.show() }
    }

    // MARK: Updates

    @objc private func checkForUpdates() { Task { await runUpdateCheck(userInitiated: true) } }
    @objc private func toggleAutoUpdates() { autoCheckUpdates.toggle() }
    @objc private func showAvailableUpdate() { if let r = updates.available { presentUpdate(r) } }

    private func runUpdateCheck(userInitiated: Bool) async {
        if userInitiated && session.isActive { return }          // never put a dialog in front of a locked keyboard
        let outcome = await updates.check()
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        switch outcome {
        case .available(let r):
            updates.available = r
            if userInitiated { presentUpdate(r) }
        case .upToDate(let v):
            updates.available = nil
            if userInitiated { simpleAlert("You're up to date", "Keypause \(v) is the latest version") }
        case .failed(let message):
            if userInitiated { simpleAlert("Couldn't check for updates", message) }
        }
    }

    private func presentUpdate(_ r: ReleaseInfo) {
        guard !session.isActive else { return }
        let brew = UpdateChecker.installedWithHomebrew
        let alert = NSAlert()
        alert.messageText = "Keypause \(r.version) is available"
        var info = "You have \(updates.currentVersion)"
        if !r.notes.isEmpty { info += "\n\n\(r.notes)" }
        if brew { info += "\n\nYou installed Keypause with Homebrew, so update with:\nbrew upgrade --cask keypause" }
        alert.informativeText = info
        alert.addButton(withTitle: brew ? "Copy Command" : "Download")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if brew {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade --cask keypause", forType: .string)
            } else {
                NSWorkspace.shared.open(r.downloadURL ?? r.pageURL)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(r.pageURL)
        default:
            break
        }
    }

    private func simpleAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
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
