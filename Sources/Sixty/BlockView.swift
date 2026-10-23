import AppKit
import SixtyCore
import SwiftUI

/// The lock screen. The main screen shows the exercise, its figure and the emergency exit; others show the
/// figure and the countdown.
struct BlockView: View {
    let model: BlockModel
    let isPrimary: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { proxy in
                let scale = Self.scale(for: proxy.size)
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    if isPrimary {
                        header(scale: scale)
                            .id(model.step)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.4), value: model.step)
                    }
                    HStack(spacing: (isPrimary ? 56 : 96) * scale) {
                        ExerciseFigureView(exerciseID: model.exerciseID)
                            .id(model.exerciseID)
                            .frame(width: (isPrimary ? 360 : 440) * scale, height: (isPrimary ? 360 : 440) * scale)
                        VStack(spacing: 18 * scale) {
                            CountdownRing(
                                secondsLeft: model.secondsLeft,
                                total: model.totalSeconds,
                                size: (isPrimary ? 190 : 260) * scale
                            )
                            StepDots(step: model.step, steps: model.steps, scale: scale)
                        }
                    }
                    .padding(.top, isPrimary ? 28 * scale : 0)
                    Spacer(minLength: 32)
                    if isPrimary {
                        EscapeSection(model: model)
                            .padding(.bottom, 48)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 48)
        }
    }

    private func header(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(L("Time to move").uppercased())
                .font(.system(size: 18 * scale, weight: .semibold))
                .tracking(4 * scale)
                .foregroundStyle(Palette.accent)
            Text(model.title)
                .font(.system(size: 64 * scale, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, 14 * scale)
            Text(model.detail)
                .font(.system(size: 24 * scale))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 820 * scale)
                .padding(.top, 12 * scale)
        }
    }

    /// 1 on a 13-inch MacBook (1512×982 pt). Larger displays scale the content up so it does not look lost;
    /// smaller ones scale it down so nothing collides with the emergency exit.
    static func scale(for size: CGSize) -> CGFloat {
        min(max(min(size.width / 1512, size.height / 982), 0.8), 1.7)
    }
}

/// "1 of 2": which exercise of the break is showing.
struct StepDots: View {
    let step: Int
    let steps: Int
    let scale: CGFloat

    var body: some View {
        if steps > 1 {
            HStack(spacing: 10 * scale) {
                ForEach(0..<steps, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Palette.accent : Color.white.opacity(0.18))
                        .frame(width: 10 * scale, height: 10 * scale)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(String(format: L("Exercise %ld of %ld"), step + 1, steps))
        }
    }
}

struct CountdownRing: View {
    let secondsLeft: Int
    let total: Int
    let size: CGFloat

    var body: some View {
        let progress = total > 0 ? CGFloat(secondsLeft) / CGFloat(total) : 0
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: size * 0.06)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsLeft)
            Text("\(secondsLeft)")
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

struct EscapeSection: View {
    @Bindable var model: BlockModel

    var body: some View {
        VStack(spacing: 10) {
            if let phrase = model.phrase, model.escapesLeft > 0 {
                Text(String(format: L("Emergency exit — %ld left today. Type:"), model.escapesLeft))
                    .font(.system(size: 13))
                Text(phrase)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                PhraseField(text: $model.typed) { typed in
                    if EscapePhrase.matches(typed, phrase) { model.onEscape?() }
                }
                .frame(width: 360, height: 26)
            } else {
                Text(L("No emergency exits left today."))
                    .font(.system(size: 13))
            }
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}

/// A text field that takes the focus at once and accepts only Latin input sources.
struct PhraseField: NSViewRepresentable {
    @Binding var text: String
    /// `true` on the dark lock screen; `false` in a normal window, which follows the system appearance.
    var onDark = true
    var onChange: (String) -> Void

    func makeNSView(context: Context) -> RomanTextField {
        let field = RomanTextField()
        field.delegate = context.coordinator
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.alignment = .center
        if onDark {
            field.textColor = .white
            field.backgroundColor = NSColor.white.withAlphaComponent(0.08)
            field.drawsBackground = true
            field.isBordered = false
            field.focusRingType = .none
        } else {
            field.bezelStyle = .roundedBezel
        }
        return field
    }

    func updateNSView(_ field: RomanTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PhraseField

        init(parent: PhraseField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange(field.stringValue)
        }
    }
}

final class RomanTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        }
        return accepted
    }
}
