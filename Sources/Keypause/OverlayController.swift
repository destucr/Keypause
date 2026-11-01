import AppKit
import SwiftUI

/// Non-activating panel: never steals focus from the app underneath (e.g. a playing video).
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Shows a small floating HUD while the keyboard is locked. Optionally dims the screens too.
@MainActor
final class OverlayController {
    private var hud: NSPanel?
    private var dimWindows: [NSWindow] = []
    private let session: CleaningSession

    init(session: CleaningSession) { self.session = session }

    func show(dimScreen: Bool) {
        hide()
        if dimScreen { showDim() }
        showHUD()
    }

    func hide() {
        hud?.orderOut(nil); hud = nil
        dimWindows.forEach { $0.orderOut(nil) }
        dimWindows.removeAll()
    }

    private func showHUD() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let notch = screen.notchSize
        let size = notch.map { CGSize(width: $0.width + 2 * 130, height: $0.height + 46) } ?? CGSize(width: 300, height: 64)

        let panel = HUDPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = notch == nil
        panel.isMovableByWindowBackground = notch == nil
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let root: AnyView = notch.map { AnyView(NotchHUDView(session: session, notch: $0)) }
            ?? AnyView(HUDView(session: session))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host

        if notch != nil {
            // Flush with the top edge, centered on the notch.
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height))
        } else {
            let f = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: f.maxX - size.width - 16, y: f.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        hud = panel
    }

    private func showDim() {
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver - 1
            w.backgroundColor = NSColor.black.withAlphaComponent(0.7)
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true // still click through to whatever is underneath
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.orderFrontRegardless()
            dimWindows.append(w)
        }
    }
}

struct HUDView: View {
    let session: CleaningSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .regular))
            VStack(alignment: .leading, spacing: 1) {
                Text("Keyboard locked").font(.system(size: 13, weight: .semibold))
                Text(timeString).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Unlock") { session.stop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 64)
        .background(.regularMaterial, in: Capsule())
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Capsule().fill(Color.accentColor.opacity(0.8))
                    .frame(width: geo.size.width * progress, height: 2)
                    .offset(y: geo.size.height - 4)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var progress: Double { session.total > 0 ? 1 - session.remaining / session.total : 0 }

    private var timeString: String {
        let s = Int(session.remaining.rounded(.up))
        return String(format: "%d:%02d remaining", s / 60, s % 60)
    }
}

extension NSScreen {
    /// Size of the camera housing (notch) if this display has one, otherwise nil.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

/// Dynamic-Island-style HUD that extends the notch: status on either side of it, controls below.
struct NotchHUDView: View {
    let session: CleaningSession
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                    Text("Locked").font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Color.clear.frame(width: notch.width) // the physical notch
                Text(timeString)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: notch.height)

            HStack(spacing: 12) {
                ProgressView(value: progress).tint(.white).frame(maxWidth: .infinity)
                Button("Unlock") { session.stop() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 22)
            .frame(height: 46)
        }
        .foregroundStyle(.white)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
    }

    private var progress: Double { session.total > 0 ? 1 - session.remaining / session.total : 0 }

    private var timeString: String {
        let s = Int(session.remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
