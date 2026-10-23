import AppKit
import SixtyCore
import SwiftUI

@MainActor @Observable
final class BlockModel {
    var secondsLeft = 60
    var totalSeconds = 60
    var title = ""
    var detail = ""
    var exerciseID = ""
    /// Which exercise of the break is showing, and how many there are.
    var step = 0
    var steps = 1
    var phrase: String?
    var escapesLeft = 0
    var typed = ""
    @ObservationIgnored var onEscape: (() -> Void)?
}

final class ShieldWindow: NSWindow {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { acceptsKey }
}

/// Covers every screen and puts the app in kiosk mode. See docs/SPEC.md, section 5.
@MainActor
final class Blocker {
    var onEscape: (() -> Void)?
    var onWatchdog: (() -> Void)?
    private(set) var isShowing = false

    private let model = BlockModel()
    private var windows: [ShieldWindow] = []
    private var primary: ShieldWindow?
    private var endsAt = Date()
    private var plan: BreakPlan?
    private var previousApp: NSRunningApplication?
    private var watchdog: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    /// No Dock, no menu bar, no Cmd+Tab, no Force Quit, no log out or restart from the Apple menu.
    private static let kiosk: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableProcessSwitching,
        .disableForceQuit,
        .disableSessionTermination,
        .disableHideApplication,
        .disableAppleMenu,
    ]

    init() {
        // Close the windows after the text field's callback returns, not inside it.
        model.onEscape = { [weak self] in
            Task { @MainActor in self?.onEscape?() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func show(endsAt: Date, plan: BreakPlan, phrase: String?, escapesLeft: Int, watchdogAfter: TimeInterval) {
        self.endsAt = endsAt
        self.plan = plan
        model.steps = plan.exercises.count
        model.totalSeconds = max(1, Int(plan.segment.rounded()))
        model.phrase = phrase
        model.escapesLeft = escapesLeft
        model.typed = ""
        showStep(0)
        update(now: Date())

        if !isShowing {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        isShowing = true
        buildWindows()
        takeOver()

        // Fail-open: whatever happens to the state machine, the lock ends.
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(watchdogAfter))
            guard let self, !Task.isCancelled, self.isShowing else { return }
            self.hide()
            self.onWatchdog?()
        }
    }

    func update(now: Date) {
        if let plan {
            // The ring counts down the current exercise; the next one takes over halfway.
            let elapsed = plan.duration - endsAt.timeIntervalSince(now)
            let step = plan.index(at: elapsed)
            if step != model.step { showStep(step) }
            model.secondsLeft = Int(ceil(plan.secondsLeftInSegment(at: elapsed)))
        }
        if isShowing { takeOver() }
    }

    private func showStep(_ step: Int) {
        guard let plan else { return }
        let exercise = plan.exercises[step]
        model.step = step
        model.title = L(exercise.title)
        model.detail = L(exercise.detail)
        model.exerciseID = exercise.id
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        watchdog?.cancel()
        watchdog = nil
        NSApp.presentationOptions = []
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        primary = nil
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        let screens = NSScreen.screens
        // The emergency field goes where you are looking: the screen with the pointer.
        let mouse = NSEvent.mouseLocation
        let main = screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? screens.first

        windows = screens.map { screen in
            let isPrimary = screen == main
            let window = ShieldWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.acceptsKey = isPrimary
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.contentView = NSHostingView(rootView: BlockView(model: model, isPrimary: isPrimary))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            if isPrimary { primary = window }
            return window
        }
    }

    /// Runs every second during a break: take the focus back if anything took it.
    private func takeOver() {
        if !NSApp.isActive {
            // `activate()` is cooperative since macOS 14 and may be refused; the older call still forces it.
            NSApp.activate(ignoringOtherApps: true)
        }
        if NSApp.presentationOptions != Self.kiosk {
            NSApp.presentationOptions = Self.kiosk
        }
        for window in windows where !window.isVisible {
            window.orderFrontRegardless()
        }
        if let primary, !primary.isKeyWindow {
            primary.makeKeyAndOrderFront(nil)
        }
    }

    private func screensChanged() {
        guard isShowing else { return }
        buildWindows()
        takeOver()
    }
}
