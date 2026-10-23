#if APP_STORE
import AppKit
import ServiceManagement
import SixtyCore
import SwiftUI

// The Mac App Store edition (built with `-DAPP_STORE`, see scripts/build-appstore.sh).
// App Review rules change three things compared with the GitHub edition:
// - no KeepAlive agent: a normal login item, and only after the user agreed (guideline 2.4.5);
// - a way to quit: "Quit Sixty…" asks for a random phrase, so it is not clicked on autopilot;
// - no self-updater: the App Store delivers updates (guideline 2.4.5).

/// The login item of the App Store edition.
@MainActor
enum LoginItem {
    private static let askedKey = "askedToStartAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Sixty: cannot change the login item: \(error.localizedDescription)")
        }
    }

    static var anotherInstanceIsRunning: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }

    /// Asks once, at the first launch: Sixty works only while it runs, but a login item needs consent.
    static func askOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)

        let alert = NSAlert()
        alert.messageText = L("Start Sixty when you log in?")
        alert.informativeText = L("Sixty works only while it runs. You can change this later in the Sixty menu.")
        alert.addButton(withTitle: L("Start at Login"))
        alert.addButton(withTitle: L("Not Now"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            setEnabled(true)
        }
    }
}

/// "Quit Sixty…": quitting is possible, but only with a fresh random phrase.
@MainActor
final class QuitPrompt {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let phrase = EscapePhrase.make()
            let view = QuitView(phrase: phrase) {
                // Quit after the text field's callback returns.
                Task { @MainActor in NSApp.terminate(nil) }
            } onCancel: { [weak self] in
                self?.close()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L("Quit Sixty")
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.contentView = NSHostingView(rootView: view)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
        window = nil
    }
}

private struct QuitView: View {
    let phrase: String
    let onMatch: () -> Void
    let onCancel: () -> Void
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 12) {
            Text(L("To quit Sixty, type:"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(phrase)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .textSelection(.disabled)
            PhraseField(text: $typed, onDark: false) { typed in
                if EscapePhrase.matches(typed, phrase) { onMatch() }
            }
            .frame(width: 320, height: 24)
            Button(L("Cancel"), action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420)
    }
}
#endif
