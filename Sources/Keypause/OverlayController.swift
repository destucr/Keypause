import AppKit
import Observation
import SwiftUI

/// Non-activating panel: never steals focus from the app underneath (e.g. a playing video).
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor @Observable
final class HUDModel { var expanded = false; var celebrating = false }

/// Shows a small floating HUD while the keyboard is locked. On notched Macs it grows out of the
/// notch like a Dynamic Island and collapses back into it; elsewhere it slides in from the top.
@MainActor
final class OverlayController {
    private var hud: NSPanel?
    private var dimWindows: [NSWindow] = []
    private let session: CleaningSession
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    /// Spring used for expand/collapse (response/damping tuned to feel like the iPhone island).
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    init(session: CleaningSession) { self.session = session }

    func show(dimScreen: Bool) {
        hideTask?.cancel()
        teardown()
        if dimScreen { showDim() }
        showHUD()
        // SwiftUI needs the view in the hierarchy before it can animate: flip on the next tick.
        DispatchQueue.main.async { [model] in withAnimation(Self.spring) { model.expanded = true } }
    }

    /// Timer ran out: swap the HUD to a short "Keys are back" moment, then collapse.
    func celebrate() {
        guard hud != nil else { return hide() }
        dimWindows.forEach { $0.orderOut(nil) }
        dimWindows.removeAll()
        withAnimation(Self.spring) { model.celebrating = true }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2400))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        guard hud != nil else { return teardown() }
        withAnimation(Self.spring) { model.expanded = false }
        dimWindows.forEach { $0.orderOut(nil) }
        dimWindows.removeAll()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self?.teardown()
        }
    }

    private func teardown() {
        hud?.orderOut(nil); hud = nil
        dimWindows.forEach { $0.orderOut(nil) }
        dimWindows.removeAll()
        model.expanded = false
        model.celebrating = false
    }

    private func showHUD() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let notch = screen.notchSize
        let size = notch.map { CGSize(width: $0.width + 2 * 130, height: $0.height + 96) } ?? CGSize(width: 360, height: 96)

        let panel = HUDPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let root: AnyView = notch.map { AnyView(NotchHUDView(session: session, model: model, notch: $0, full: size)) }
            ?? AnyView(HUDView(session: session, model: model, full: size))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host
        host.layoutSubtreeIfNeeded()

        // Notch: flush with the top edge, centered on the notch. Otherwise: top-right under the menu bar.
        if notch != nil {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height))
        } else {
            let f = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: f.maxX - size.width - 8, y: f.maxY - size.height))
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

extension NSScreen {
    /// Size of the camera housing (notch) if this display has one, otherwise nil.
    /// Measured at runtime, so it is right for every notched Mac (14"/16" Pro, Air 13"/15", future models).
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

private func timeString(_ remaining: TimeInterval, suffix: String = "") -> String {
    let s = Int(remaining.rounded(.up))
    return String(format: "%d:%02d%@", s / 60, s % 60, suffix)
}

@MainActor private func progress(_ session: CleaningSession) -> Double {
    session.total > 0 ? 1 - session.remaining / session.total : 0
}

/// Dynamic-Island-style HUD: a black shape that grows out of the notch, status on either side, controls below.
struct NotchHUDView: View {
    static let ear: CGFloat = 16
    let session: CleaningSession
    let model: HUDModel
    let notch: CGSize
    let full: CGSize

    var body: some View {
        let open = model.expanded
        ZStack(alignment: .top) {
            NotchShape(ear: open ? Self.ear : 0, bottom: open ? 28 : 9)
                .fill(.black)
                .frame(width: open ? full.width : notch.width, height: open ? full.height : notch.height)

            DawnScene(deadline: session.deadline, total: session.total, done: model.celebrating)
                .frame(width: full.width, height: full.height)
                .mask(alignment: .top) {
                    NotchShape(ear: open ? Self.ear : 0, bottom: open ? 28 : 9)
                        .frame(width: open ? full.width : notch.width, height: open ? full.height : notch.height)
                }

            content
                .frame(width: full.width - 2 * Self.ear, height: full.height) // inside the body, clear of the ears
                .opacity(open ? 1 : 0)
                .animation(open ? .easeOut(duration: 0.22).delay(0.14) : .easeIn(duration: 0.1), value: open)
        }
        .frame(width: full.width, height: full.height, alignment: .top)
    }

    /// White on the night sky, navy on the morning sky: whichever reads better against what is actually behind it.
    private func ink(at depth: Double) -> Color {
        let p = model.celebrating ? 1 : progress(session)
        return DawnPalette.prefersDarkText(p, at: depth) ? DawnPalette.inkColor : .white
    }

    /// A soft halo that widens the contrast margin, most useful where white and plum text are about equally readable.
    private func textHalo(at depth: Double) -> Color {
        DawnPalette.prefersDarkText(model.celebrating ? 1 : progress(session), at: depth) ? Color.white.opacity(0.45) : Color.black.opacity(0.55)
    }

    private var unlockTint: Color {
        DawnPalette.prefersDarkText(model.celebrating ? 1 : progress(session), at: 0.62) ? DawnPalette.inkColor : Color.white.opacity(0.28)
    }

    private var content: some View {
        VStack(spacing: 0) {
            // status flanking the notch
            HStack(spacing: 0) {
                Text(model.celebrating ? "Keys are back" : "Locked")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notch.width) // the physical notch
                Text(model.celebrating ? "" : timeString(session.remaining))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(height: notch.height)
            .foregroundStyle(ink(at: 0.1))
            .shadow(color: textHalo(at: 0.1), radius: 3, y: 1)

            // Kip on the left; progress, one quiet line and Unlock on the right
            HStack(spacing: 16) {
                KipView(state: kipState(session, celebrating: model.celebrating)).frame(width: 72, height: 72)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        let copy = stageCopy(remaining: session.remaining, total: session.total)
                        Text(model.celebrating ? "Good morning!" : copy.title)
                            .font(.system(size: 14, weight: .semibold))
                        Text(model.celebrating ? "Your keys are back. Happy typing." : copy.line)
                            .font(.system(size: 11)).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    if !model.celebrating {
                        Button("Unlock") { session.stop() }.buttonStyle(.borderedProminent).controlSize(.small).tint(unlockTint)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .foregroundStyle(ink(at: 0.62))
            .shadow(color: textHalo(at: 0.62), radius: 3, y: 1)
        }
        .animation(.easeInOut(duration: 0.5), value: ink(at: 0.62) == .white)
        .animation(.easeInOut(duration: 0.5), value: ink(at: 0.1) == .white)
    }
}

/// Floating pill for Macs without a notch: slides down from the menu bar.
struct HUDView: View {
    let session: CleaningSession
    let model: HUDModel
    let full: CGSize

    var body: some View {
        let open = model.expanded
        HStack(spacing: 12) {
            KipView(state: kipState(session, celebrating: model.celebrating)).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.celebrating ? "Good morning!" : stageCopy(remaining: session.remaining, total: session.total).title).font(.system(size: 13, weight: .semibold))
                Text(model.celebrating ? "Your keys are back." : timeString(session.remaining, suffix: " until sunrise"))
                    .font(.system(size: 12).monospacedDigit()).opacity(0.85)
            }
            Spacer(minLength: 8)
            if !model.celebrating { Button("Unlock") { session.stop() }.buttonStyle(.borderedProminent) }
        }
        .padding(.horizontal, 16)
        .frame(width: 340, height: 80)
        .background(DawnScene(deadline: session.deadline, total: session.total, done: model.celebrating).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .foregroundStyle(DawnPalette.prefersDarkText(model.celebrating ? 1 : progress(session), at: 0.5) ? DawnPalette.inkColor : .white)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .scaleEffect(open ? 1 : 0.85, anchor: .top)
        .offset(y: open ? 8 : -70)
        .opacity(open ? 1 : 0)
        .frame(width: full.width, height: full.height, alignment: .top)
    }
}

/// The island's silhouette: concave "ears" at the top that flare into the menu bar (so it grows out of
/// the notch instead of sitting on it), a straight body, and rounded bottom corners. Both radii animate.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let e = max(0, min(ear, h / 2, w / 4))
        let b = max(0, min(bottom, h - e, (w - 2 * e) / 2))
        let k: CGFloat = 0.5523 // circular-arc approximation for cubic curves
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // top-right ear: concave, sweeps in and down
        p.addCurve(to: CGPoint(x: w - e, y: e),
                   control1: CGPoint(x: w - e * k, y: 0), control2: CGPoint(x: w - e, y: e - e * k))
        p.addLine(to: CGPoint(x: w - e, y: h - b))
        // bottom-right: convex
        p.addCurve(to: CGPoint(x: w - e - b, y: h),
                   control1: CGPoint(x: w - e, y: h - b + b * k), control2: CGPoint(x: w - e - b + b * k, y: h))
        p.addLine(to: CGPoint(x: e + b, y: h))
        // bottom-left: convex
        p.addCurve(to: CGPoint(x: e, y: h - b),
                   control1: CGPoint(x: e + b - b * k, y: h), control2: CGPoint(x: e, y: h - b + b * k))
        p.addLine(to: CGPoint(x: e, y: e))
        // top-left ear: concave
        p.addCurve(to: CGPoint(x: 0, y: 0),
                   control1: CGPoint(x: e, y: e - e * k), control2: CGPoint(x: e * k, y: 0))
        p.closeSubpath()
        return p
    }
}

/// How long before the end Kip starts waking (long enough for a breath to finish and the wake-up to play).
private func wakeLead(_ total: TimeInterval) -> TimeInterval { min(11, total * 0.32) }

/// Where we are in Kip's night, as a title and one plain line. Driven by time left, so even a 30 s session tells the whole story.
@MainActor private func stageCopy(remaining r: TimeInterval, total: TimeInterval) -> (title: String, line: String) {
    let lead = wakeLead(total), span = max(1, total - lead), elapsed = total - r
    if r <= lead - 4 { return ("Rise and shine!", "Your keys are coming back.") }
    if r <= lead { return ("Kip is stirring…", "Sunrise is almost here.") }
    if elapsed < span * 0.4 { return ("Shh, your keys are napping.", "Wipe away. They wake at sunrise.") }
    return ("Still dreaming…", "Your keyboard is locked until sunrise.")
}

/// Kip sleeps most of the night, wakes `wakeLead` before the end, and cheers for the last few seconds.
@MainActor private func kipState(_ session: CleaningSession, celebrating: Bool) -> KipState {
    if celebrating { return .cheer }
    let r = session.remaining
    return r <= 3.4 ? .cheer : (r <= wakeLead(session.total) ? .awake : .sleep)
}
