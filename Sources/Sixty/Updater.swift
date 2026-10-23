import AppKit
import Security
import SixtyCore

/// Silent updates. Twice a day Sixty asks GitHub for the latest release. If it is newer, Sixty downloads
/// the ZIP, checks that SAAC's Developer ID signed it, and swaps the app between breaks.
/// Then it exits, and launchd (KeepAlive) starts the new version. No windows, no buttons.
@MainActor
final class Updater {
    /// Only code signed with this Team ID is installed. Forks must change it to their own.
    nonisolated static let teamID = "JVW2N74WL3"
    nonisolated static let bundleID = "pro.saac.sixty"

    struct Staged: Sendable {
        let version: Version
        let app: URL
    }

    private let defaults = UserDefaults.standard
    private let currentVersion = Links.version
    private let beforeRestart: () -> Void
    private var staged: Staged?
    private var busy = false

    private var nextCheck: Date? {
        get { defaults.object(forKey: "nextUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "nextUpdateCheck") }
    }

    /// Updates only an installed copy that launchd keeps alive: never a build folder, the demo or `swift run`.
    static var isSupported: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
        let installed = folder == "/Applications" || folder == NSHomeDirectory() + "/Applications"
        return installed && LoginAgent.isAgentProcess
    }

    init(beforeRestart: @escaping () -> Void) {
        self.beforeRestart = beforeRestart
    }

    func tick(now: Date, phase: Phase) {
        guard !busy else { return }
        if let staged {
            if UpdatePolicy.canInstall(during: phase) { install(staged) }
            return
        }
        guard UpdatePolicy.isCheckDue(next: nextCheck, now: now) else { return }
        busy = true
        let currentVersion = currentVersion
        Task {
            let result = await Self.fetch(currentVersion: currentVersion)
            nextCheck = UpdatePolicy.nextCheck(after: Date(), succeeded: result.checked)
            staged = result.staged
            busy = false
            if let staged = result.staged { NSLog("Sixty: update \(staged.version) is ready") }
        }
    }

    private func install(_ update: Staged) {
        busy = true
        do {
            _ = try FileManager.default.replaceItemAt(Bundle.main.bundleURL, withItemAt: update.app)
            NSLog("Sixty: updated to \(update.version), restarting")
            beforeRestart()
            // A new process, outside our launchd job, registers the agent for the new signature
            // and launchd starts the new version. `open -n` keeps it out of our process group.
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-n", Bundle.main.bundleURL.path, "--args", "--reregister"]
            try open.run()
            exit(0)
        } catch {
            NSLog("Sixty: cannot install update \(update.version): \(error.localizedDescription)")
            staged = nil
            busy = false
            nextCheck = UpdatePolicy.nextCheck(after: Date(), succeeded: false)
        }
    }

    // MARK: - Off the main actor

    private struct FetchResult: Sendable {
        var checked = false
        var staged: Staged?
    }

    private nonisolated static func fetch(currentVersion: String) async -> FetchResult {
        var result = FetchResult()
        do {
            var request = URLRequest(url: UpdatePolicy.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Sixty/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            // 404: no release published yet. That is a successful check with nothing to do.
            guard status == 200 || status == 404 else { return result }
            result.checked = true
            guard status == 200,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                  let update = UpdatePolicy.update(from: release, currentVersion: currentVersion)
            else { return result }
            result.staged = try await stage(update)
        } catch {
            NSLog("Sixty: update check failed: \(error.localizedDescription)")
        }
        return result
    }

    /// Downloads and unpacks the ZIP into Application Support, then verifies it. Returns `nil` if anything is off.
    private nonisolated static func stage(_ update: AvailableUpdate) async throws -> Staged? {
        let (archive, response) = try await URLSession.shared.download(from: update.archiveURL)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Sixty/Updates", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()

        let app = folder.appendingPathComponent("Sixty.app", isDirectory: true)
        guard ditto.terminationStatus == 0,
              isSignedBySAAC(app),
              shortVersion(of: app) == update.version.description
        else {
            NSLog("Sixty: rejected update \(update.version): bad archive, signature or version")
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        return Staged(version: update.version, app: app)
    }

    /// A valid Developer ID signature from our team, for our bundle ID, on every architecture and nested item.
    nonisolated static func isSignedBySAAC(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let text = """
            identifier "\(bundleID)" and anchor apple generic \
            and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
            and certificate leaf[subject.OU] = "\(teamID)"
            """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private nonisolated static func shortVersion(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
}
