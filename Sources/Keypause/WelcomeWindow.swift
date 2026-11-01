import AppKit
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
            w.setContentSize(NSSize(width: 360, height: 340))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct WelcomeView: View {
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 84, height: 84)
            Text("Keypause is ready").font(.title2.weight(.semibold))
            Text("It lives in your menu bar, up top, as a small keycap icon. Click it any time to start cleaning.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if !KeyboardLock.hasPermission { permissionNote }
            }

            Spacer(minLength: 0)
            HStack {
                Button("Close", action: onClose)
                Button("Start Cleaning", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 360, height: 340)
    }

    private var permissionNote: some View {
        VStack(spacing: 8) {
            Label("One-time setup: allow Accessibility so Keypause can lock the keys.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Button("Grant Access…") {
                KeyboardLock.requestPermission()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
