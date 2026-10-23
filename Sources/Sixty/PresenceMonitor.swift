import AppKit
import CoreGraphics

/// How long you have not touched the Mac. A locked screen counts as idle since the moment it locked.
@MainActor
final class PresenceMonitor {
    private var lockedSince: Date?
    private var tokens: [NSObjectProtocol] = []
    /// `kCGAnyInputEventType`: keyboard, mouse, trackpad.
    private let anyInput = CGEventType(rawValue: ~0)!

    init() {
        let center = DistributedNotificationCenter.default()
        tokens.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockedSince = Date() }
        })
        tokens.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockedSince = nil }
        })
    }

    var isLocked: Bool { lockedSince != nil }

    func idleSeconds(at now: Date) -> TimeInterval {
        let input = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let locked = lockedSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(input, locked)
    }
}
