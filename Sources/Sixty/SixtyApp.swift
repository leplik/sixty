import AppKit
import SixtyCore

@main
@MainActor
enum SixtyApp {
    static func main() {
        let arguments = CommandLine.arguments
        #if APP_STORE
        if arguments.contains("--disable") {
            LoginItem.setEnabled(false)
            exit(0)
        }
        #else
        if arguments.contains("--disable") { exit(LoginAgent.disable()) }
        // If the agent does not come up, this process carries on as Sixty, so no break is lost.
        if arguments.contains("--reregister"), LoginAgent.reregister() { exit(0) }
        #endif
        if arguments.contains("--probe") { exit(Probe.run()) }
        if let flag = arguments.firstIndex(of: "--render-figures") {
            exit(FigureSheets.render(to: arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "figures"))
        }
        if let flag = arguments.firstIndex(of: "--render-media") {
            exit(MediaRenderer.run(repository: arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "."))
        }
        if arguments.contains("--version") {
            print(Links.version)
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = ProcessInfo.processInfo.environment["SIXTY_DEMO"] == "1"
        #if APP_STORE
        if !demo, LoginItem.anotherInstanceIsRunning {
            NSApp.terminate(nil)
            return
        }
        #else
        if !demo {
            switch LoginAgent.bootstrap() {
            case .exit:
                NSApp.terminate(nil)
                return
            case .run, .runUntilAgentStarts:
                break
            }
            // A stand-in hands over as soon as the launchd agent runs.
            if LoginAgent.isStandIn {
                Task { @MainActor in
                    while true {
                        try? await Task.sleep(for: .seconds(5))
                        if LoginAgent.anotherInstanceIsRunning { NSApp.terminate(nil) }
                    }
                }
            }
        }
        #endif
        let controller = AppController(timing: demo ? .demo : .standard, store: Store(demo: demo), demo: demo)
        controller.start()
        self.controller = controller
        #if APP_STORE
        if !demo { LoginItem.askOnce() }
        #endif
    }
}

/// `Sixty --probe`: prints what Sixty sees right now. Useful to find the bundle ID of a call app.
enum Probe {
    static func run() -> Int32 {
        let snapshot = DeviceSnapshot(audioClients: AudioClients.current(), cameraInUse: Camera.inUse())
        print("Cameras found: \(Camera.count()), in use: \(snapshot.cameraInUse ? "yes" : "no")")
        if snapshot.audioClients.isEmpty { print("No app uses the microphone or the speaker.") }
        for client in snapshot.audioClients {
            var devices: [String] = []
            if client.usesMicrophone { devices.append("microphone") }
            if client.usesSpeaker { devices.append("speaker") }
            print("\(client.bundleID): \(devices.joined(separator: " + "))")
        }
        switch CallPolicy.standard.signal(for: snapshot) {
        case nil: print("Call: no")
        case .camera: print("Call: yes (camera)")
        case .microphone(let app): print("Call: yes (\(app) uses the microphone)")
        case .speaker(let app): print("Call: yes (\(app) plays audio)")
        }
        return 0
    }
}
