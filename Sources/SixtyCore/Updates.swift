import Foundation

/// A release version `major.minor.patch`. A leading "v" and a pre-release suffix are accepted.
public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        guard let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first else { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = part, number >= 0 else { return nil }
            numbers.append(number)
        }
        numbers += Array(repeating: 0, count: 3 - numbers.count)
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public static func < (a: Version, b: Version) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// The fields Sixty reads from GitHub's `GET /repos/{owner}/{repo}/releases/latest`.
public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: Version
    public let archiveURL: URL
}

/// Rules for the silent updater. See docs/SPEC.md, section "Updates".
public enum UpdatePolicy {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/leplik/sixty/releases/latest")!
    public static let checkInterval: TimeInterval = 12 * 60 * 60
    public static let retryInterval: TimeInterval = 60 * 60

    /// The update to download, or `nil` if the release is not newer or has no app archive.
    public static func update(from release: GitHubRelease, currentVersion: String) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease, let version = Version(release.tagName) else { return nil }
        // A development build (no valid version) takes any release.
        if let current = Version(currentVersion), !(current < version) { return nil }
        let name = "Sixty-\(version).zip"
        guard let asset = release.assets.first(where: { $0.name == name }),
              asset.browserDownloadURL.scheme == "https",
              asset.browserDownloadURL.host == "github.com"
        else { return nil }
        return AvailableUpdate(version: version, archiveURL: asset.browserDownloadURL)
    }

    /// Next check: twice a day after a successful check, after an hour if the check failed.
    public static func nextCheck(after now: Date, succeeded: Bool) -> Date {
        now.addingTimeInterval(succeeded ? checkInterval : retryInterval)
    }

    public static func isCheckDue(next: Date?, now: Date) -> Bool {
        guard let next else { return true }
        // A next check far in the future means the clock went backwards: check now.
        return now >= next || next.timeIntervalSince(now) > checkInterval
    }

    /// Install only between breaks: the restart must never cut a warning, a break or a postponed break.
    public static func canInstall(during phase: Phase) -> Bool {
        phase == .working
    }
}
