import AppKit
import SwiftUI

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Dims every display with a calm full-screen overlay while the keyboard is locked.
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private let session: CleaningSession

    init(session: CleaningSession) { self.session = session }

    func show() {
        hide()
        for (index, screen) in NSScreen.screens.enumerated() {
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false, screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            // Only the primary display shows the controls; others are just dimmed.
            let isPrimary = index == 0
            window.contentView = NSHostingView(
                rootView: OverlayView(session: session, showsControls: isPrimary)
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            if isPrimary { window.makeKey() }
            windows.append(window)
        }
        NSApp.activate()
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

struct OverlayView: View {
    let session: CleaningSession
    let showsControls: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
            if showsControls {
                VStack(spacing: 22) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 64, weight: .thin))
                    Text("Keyboard Locked")
                        .font(.system(size: 28, weight: .semibold))
                    Text(timeString)
                        .font(.system(size: 56, weight: .light).monospacedDigit())
                        .contentTransition(.numericText())
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                        .tint(.white)
                    Text("Go ahead and wipe it down. Every key is disabled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Unlock Now") { session.stop() }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.none)
                        .padding(.top, 8)
                }
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
    }

    private var progress: Double {
        session.total > 0 ? 1 - session.remaining / session.total : 0
    }

    private var timeString: String {
        let s = Int(session.remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
