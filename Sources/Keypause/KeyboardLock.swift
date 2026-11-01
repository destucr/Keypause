import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Swallows all keyboard input (including media / function keys) through a CGEventTap.
/// Requires the Accessibility permission. The mouse and trackpad are left untouched
/// so the user can always click "Unlock".
final class KeyboardLock {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// When true the tap lets every event through. Used for permission probes, so checking
    /// permission can never swallow a real keystroke.
    private let passthrough: Bool

    /// Called if macOS turns the tap off and it cannot be turned back on (e.g. permission revoked),
    /// so the UI never claims the keyboard is locked when it is not.
    var onLost: (() -> Void)?

    init(passthrough: Bool = false) { self.passthrough = passthrough }

    var isActive: Bool { tap != nil }

    enum PermissionState {
        case needed      // macOS has not allowed Keypause yet
        case blocked     // switched on, but macOS still refuses (stale grant after an update, or Input Monitoring is needed too)
        case allowed
    }

    /// The real test: can we actually create the event tap? (`AXIsProcessTrusted` alone can disagree
    /// with what macOS lets us do, e.g. after an update changes the app's code signature.)
    static var permissionState: PermissionState {
        guard AXIsProcessTrusted() else { return .needed }
        let probe = KeyboardLock(passthrough: true)   // lets every key through; checking can never swallow typing
        let ok = probe.start()
        probe.stop()
        return ok ? .allowed : .blocked
    }
    static var hasPermission: Bool { permissionState == .allowed }

    /// Clears this app's own (possibly stale) Accessibility / Input Monitoring grants, so macOS asks fresh.
    /// After an update, macOS can keep listing an app as allowed while no longer trusting the new build.
    @discardableResult
    static func resetStaleGrants() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        var ok = true
        for service in ["Accessibility", "ListenEvent"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, id]
            do { try p.run(); p.waitUntilExit(); ok = ok && p.terminationStatus == 0 } catch { ok = false }
        }
        return ok
    }

    /// Also asks for Input Monitoring, which some macOS versions require for keyboard taps.
    static func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
    }

    /// Shows the system Accessibility prompt if permission is missing.
    @discardableResult
    static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let systemDefined: CGEventType = CGEventType(rawValue: 14)! // NX_SYSDEFINED: media keys, brightness, volume…
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, systemDefined]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let lock = Unmanaged<KeyboardLock>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = lock.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    if !CGEvent.tapIsEnabled(tap: tap) { lock.onLost?() } // could not recover: tell the UI
                }
                return Unmanaged.passUnretained(event)
            }
            return lock.passthrough ? Unmanaged.passUnretained(event) : nil // nil drops the event
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    deinit { stop() }
}


/// The single place that asks macOS for permission, so the user never sees stacked or repeated prompts:
///  - the first request shows macOS's own prompt once; later requests just open the right Settings pane,
///  - Accessibility and Input Monitoring are never requested together,
///  - only the welcome window guides the user (no extra alerts).
@MainActor
final class PermissionCoordinator {
    static let shared = PermissionCoordinator()
    private var askedAccessibility = false
    private var askedInputMonitoring = false

    func requestAccessibility() {
        if !askedAccessibility { askedAccessibility = true; KeyboardLock.requestPermission() }   // macOS's own prompt, once
        else { openSettings("Privacy_Accessibility") }
    }

    func requestInputMonitoring() {
        if !askedInputMonitoring { askedInputMonitoring = true; KeyboardLock.requestInputMonitoring() }
        openSettings("Privacy_ListenEvent")
    }

    /// Clears this app's stale grants and asks again, once.
    func resetAndRetry() {
        KeyboardLock.resetStaleGrants()
        askedAccessibility = false
        askedInputMonitoring = false
        requestAccessibility()
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
}
