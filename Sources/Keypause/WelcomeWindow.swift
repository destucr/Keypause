import AppKit
import Observation
import SwiftUI

/// Shown when the user opens Keypause themselves (Spotlight, Finder, Dock…), so a
/// menu-bar-only app never looks like "nothing happened".
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    private let onStart: () -> Void

    init(onStart: @escaping () -> Void) { self.onStart = onStart }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView(
                onStart: { [weak self] in self?.window?.close(); self?.onStart() },
                onClose: { [weak self] in self?.window?.close() }
            ))
            w.setContentSize(NSSize(width: 440, height: 520))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// Watches the permission while the welcome window is open, so the window reacts the moment it changes.
@MainActor @Observable
final class PermissionWatcher {
    private(set) var state = KeyboardLock.permissionState
    private(set) var justGranted = false
    private(set) var waitingSince: Date?      // set once the user has been sent off to switch it on
    private(set) var tick = 0                 // refreshes "waiting too long" while nothing else changes
    private var timer: Timer?

    var granted: Bool { state == .allowed }
    var waitingLong: Bool { waitingSince.map { Date().timeIntervalSince($0) > 20 } ?? false }

    func start() {
        stop()
        state = KeyboardLock.permissionState
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    func markRequested() { waitingSince = Date() }

    private func poll() {
        let now = KeyboardLock.permissionState
        if now == .allowed {
            if state != .allowed {
                justGranted = true              // Kip cheers for a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in self?.justGranted = false }
            }
            waitingSince = nil
        }
        state = now
        tick += 1
    }
}

struct WelcomeView: View {
    let onStart: () -> Void
    let onClose: () -> Void
    @State private var watcher = PermissionWatcher()

    private var title: String {
        switch watcher.state {
        case .allowed: return "You're all set"
        case .blocked: return "One more step"
        case .needed:  return "Welcome to Keypause"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            KipView(state: watcher.justGranted ? .cheer : .awake).frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text("Press one button. Wipe your keyboard. Done.").foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                permissionRow

                StepRow(number: 2, done: false,
                        title: "Start from anywhere",
                        detail: "Or click the keycap in the menu bar. On a notched Mac it can hide behind the notch.") {
                    Text("⌃⌥⌘K")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                StepRow(number: 3, done: false,
                        title: "Try it",
                        detail: "Locks for the time you pick, then gives the keys back.") {
                    Button("Start Cleaning", action: onStart)
                        .disabled(!watcher.granted)
                }
                .opacity(watcher.granted ? 1 : 0.55)
            }

            Spacer(minLength: 0)
            Button(watcher.granted ? "Done" : "Close", action: onClose).buttonStyle(.link)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 440, height: 520)
        .animation(.easeInOut(duration: 0.25), value: watcher.state)
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
    }

    /// Step 1 is the real hurdle, so it tells you exactly where you are: needed, waiting, not working, or allowed.
    @ViewBuilder private var permissionRow: some View {
        switch watcher.state {
        case .allowed:
            StepRow(number: 1, done: true, title: "Allow keyboard control", detail: "Keypause can switch your keys off.") {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout.weight(.medium))
            }

        case .blocked:
            StepRow(number: 1, done: false, warn: true, title: "It's on, but macOS isn't accepting it",
                    detail: "This happens after an update, or when Input Monitoring is needed too. A reset fixes it in most cases.") {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Reset and retry") { watcher.markRequested(); PermissionCoordinator.shared.resetAndRetry() }
                        .buttonStyle(.borderedProminent)
                    Button("Open Input Monitoring") { watcher.markRequested(); PermissionCoordinator.shared.requestInputMonitoring() }
                        .buttonStyle(.link).font(.caption)
                }
            }

        case .needed:
            if watcher.waitingSince != nil {
                StepRow(number: 1, done: false, title: "Waiting for you…",
                        detail: watcher.waitingLong
                            ? "Not seeing it? Switch Keypause on in the list. If it already is, reset it."
                            : "Switch Keypause on in System Settings. This updates here by itself.") {
                    VStack(alignment: .trailing, spacing: 6) {
                        ProgressView().controlSize(.small)
                        if watcher.waitingLong {
                            Button("Reset and retry") { PermissionCoordinator.shared.resetAndRetry() }.buttonStyle(.link).font(.caption)
                        } else {
                            Button("Open Settings again") { PermissionCoordinator.shared.requestAccessibility() }.buttonStyle(.link).font(.caption)
                        }
                    }
                }
            } else {
                StepRow(number: 1, done: false, title: "Allow keyboard control",
                        detail: "macOS needs your OK before an app can switch keys off.") {
                    Button("Grant Access…") { watcher.markRequested(); PermissionCoordinator.shared.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct StepRow<Trailing: View>: View {
    let number: Int
    let done: Bool
    var warn = false
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : (warn ? Color.orange : Color.secondary.opacity(0.18))).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                else if warn { Image(systemName: "exclamationmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                else { Text("\(number)").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Dev/QA only (`--kip-preview`): all of Kip's poses side by side on neutral grey, for silhouette checks.
@MainActor
func makeKipPreviewWindow() -> NSWindow {
    let view = HStack(spacing: 0) {
        KipView(state: .sleep).frame(width: 260, height: 260)
        KipView(state: .awake).frame(width: 260, height: 260)
        KipView(state: .cheer).frame(width: 260, height: 260)
    }
    .padding(10)
    .background(Color(white: 0.5))
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 280),
                     styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = "Kip preview"
    w.contentView = NSHostingView(rootView: view)
    w.isReleasedWhenClosed = false
    w.center()
    w.makeKeyAndOrderFront(nil)
    NSApp.activate()
    return w
}
