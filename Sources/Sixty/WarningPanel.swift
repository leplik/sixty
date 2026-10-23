import AppKit
import SixtyCore
import SwiftUI

@MainActor @Observable
final class WarningModel {
    var secondsLeft = 60
    var exerciseTitle = ""
    var exerciseID = ""
}

struct WarningView: View {
    let model: WarningModel

    var body: some View {
        HStack(spacing: 12) {
            // A tiny live preview of the coming exercise.
            ExerciseFigureView(exerciseID: model.exerciseID, style: .badge)
                .id(model.exerciseID)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: L("Break in %ld s"), model.secondsLeft))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text(String(format: L("Next: %@"), model.exerciseTitle))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The 60-second countdown in the top-right corner. No buttons, click-through, never takes the focus.
@MainActor
final class WarningPanel {
    private var panel: NSPanel?
    private let model = WarningModel()
    private var endsAt = Date()

    func show(endsAt: Date, plan: BreakPlan) {
        self.endsAt = endsAt
        model.exerciseTitle = plan.exercises.map { L($0.title) }.joined(separator: " + ")
        model.exerciseID = plan.exercises[0].id
        update(now: Date())
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
    }

    func update(now: Date) {
        model.secondsLeft = max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    /// Drops the panel: its live figure must not keep animating while hidden.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: WarningView(model: model))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        return panel
    }

    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16))
    }
}
