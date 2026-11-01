import Foundation
import IOKit.pwr_mgt
import Observation

/// Owns the state of one cleaning run: keyboard lock, countdown, and sleep prevention.
@MainActor
@Observable
final class CleaningSession {
    enum StartResult { case started, needsPermission }

    private(set) var isActive = false
    private(set) var remaining: TimeInterval = 0
    private(set) var total: TimeInterval = 0

    var onChange: (() -> Void)?

    private let lock = KeyboardLock()
    private var timer: Timer?
    private var deadline: Date?
    private var assertionID: IOPMAssertionID = 0

    func start(duration: TimeInterval) -> StartResult {
        guard !isActive else { return .started }
        guard KeyboardLock.hasPermission, lock.start() else { return .needsPermission }

        total = duration
        remaining = duration
        deadline = Date().addingTimeInterval(duration)
        isActive = true
        preventSleep()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onChange?()
        return .started
    }

    func stop() {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        lock.stop()
        allowSleep()
        isActive = false
        remaining = 0
        onChange?()
    }

    private func tick() {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining <= 0 { stop() }
    }

    // Keep the display awake so the screen saver / sleep never interrupts cleaning.
    private func preventSleep() {
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Keypause is locking the keyboard for cleaning" as CFString,
            &assertionID
        )
    }

    private func allowSleep() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
