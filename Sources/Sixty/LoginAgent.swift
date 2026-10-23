#if !APP_STORE  // The App Store edition uses LoginItem (AppStoreEdition.swift).
import AppKit
import ServiceManagement

enum LaunchDecision {
    case run
    case exit
    /// We just registered the agent; launchd starts its own instance, then this one exits.
    case runUntilAgentStarts
}

/// Sixty runs as a KeepAlive LaunchAgent, so killing it does not stop it. See docs/SPEC.md, sections 8 and 9.
@MainActor
enum LoginAgent {
    static let label = "pro.saac.sixty.agent"

    private static var service: SMAppService {
        .agent(plistName: "\(label).plist")
    }

    /// launchd sets XPC_SERVICE_NAME to the job label for the processes it starts.
    static var isAgentProcess: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
    }

    static var anotherInstanceIsRunning: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }

    static func bootstrap() -> LaunchDecision {
        // `swift run` during development: no bundle, no agent.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .run }
        if isAgentProcess { return .run }
        if anotherInstanceIsRunning { return .exit }

        switch service.status {
        case .enabled:
            // Registered, but not running (for example `launchctl bootout`). Run here until next login.
            return .run
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            return .run
        default:
            do {
                try service.register()
            } catch {
                NSLog("Sixty: cannot register the login agent: \(error.localizedDescription)")
                return .run
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return .run
            }
            return .runUntilAgentStarts
        }
    }

    /// `Sixty --reregister`: registers the agent again for the app as it is on disk now, after an update or
    /// a reinstall. Returns `true` once launchd really runs the agent.
    ///
    /// Seen on macOS 26: right after the bundle was replaced, launchd may refuse to spawn the agent
    /// (exit 78, EX_CONFIG) although registration succeeds; a later attempt for the same bundle works.
    /// So: check that the agent runs, and retry with a growing pause.
    static func reregister() -> Bool {
        for attempt in 1...3 {
            try? service.unregister()
            Thread.sleep(forTimeInterval: 2 * Double(attempt))
            do {
                try service.register()
            } catch {
                NSLog("Sixty: cannot register the login agent: \(error.localizedDescription)")
                continue
            }
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 1)
                if agentPID() != nil { return true }
            }
            NSLog("Sixty: the login agent did not start (attempt \(attempt) of 3)")
        }
        return false
    }

    /// The pid of the running agent, read from `launchctl print`. Works without a run loop.
    static func agentPID() -> Int32? {
        let launchctl = Process()
        let output = Pipe()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["print", "gui/\(getuid())/\(label)"]
        launchctl.standardOutput = output
        launchctl.standardError = FileHandle.nullDevice
        guard (try? launchctl.run()) != nil else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        launchctl.waitUntilExit()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "pid", let pid = Int32(parts[1]) { return pid }
        }
        return nil
    }

    /// An installed copy that launchd did not start: it covers for the agent until the agent runs.
    static var isStandIn: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && !isAgentProcess
    }

    /// `Sixty --disable`: the deliberate way to turn Sixty off.
    static func disable() -> Int32 {
        do {
            try service.unregister()
            print("Sixty is off. Open Sixty.app to turn it on again.")
            return 0
        } catch {
            print("Sixty: cannot turn off: \(error.localizedDescription)")
            return 1
        }
    }
}
#endif
