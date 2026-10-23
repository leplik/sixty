import Foundation
import Testing
@testable import SixtyCore

@Suite("Version")
struct VersionTests {
    @Test(arguments: [
        ("1.2.3", "1.2.3"),
        ("v1.2.3", "1.2.3"),
        ("V0.10.0", "0.10.0"),
        ("1.2", "1.2.0"),
        ("2", "2.0.0"),
        ("1.2.3-beta.1", "1.2.3"),
        (" 0.1.0 ", "0.1.0"),
    ])
    func parses(text: String, expected: String) {
        #expect(Version(text)?.description == expected)
    }

    @Test(arguments: ["", "v", "abc", "1..2", "1.2.3.4", "1.-2.3", "dev"])
    func rejects(text: String) {
        #expect(Version(text) == nil)
    }

    @Test func comparesNumerically() {
        #expect(Version("0.9.0")! < Version("0.10.0")!)
        #expect(Version("1.0.0")! < Version("1.0.1")!)
        #expect(!(Version("1.0.0")! < Version("v1.0")!))
    }
}

@Suite("UpdatePolicy")
struct UpdatePolicyTests {
    private func release(
        tag: String = "v0.2.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [String]? = nil
    ) throws -> GitHubRelease {
        let version = Version(tag)?.description ?? tag
        let names = assets ?? ["Sixty-\(version).dmg", "Sixty-\(version).zip"]
        let assetJSON = names.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/leplik/sixty/releases/download/\#(tag)/\#($0)","size":1}"#
        }
        let json = #"{"tag_name":"\#(tag)","name":"x","draft":\#(draft),"prerelease":\#(prerelease),"assets":[\#(assetJSON.joined(separator: ","))]}"#
        return try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    @Test func offersANewerRelease() throws {
        let update = UpdatePolicy.update(from: try release(), currentVersion: "0.1.0")
        #expect(update?.version == Version("0.2.0"))
        #expect(update?.archiveURL.absoluteString == "https://github.com/leplik/sixty/releases/download/v0.2.0/Sixty-0.2.0.zip")
    }

    @Test(arguments: ["0.2.0", "0.3.0", "1.0.0"])
    func ignoresTheSameOrAnOlderRelease(current: String) throws {
        #expect(UpdatePolicy.update(from: try release(), currentVersion: current) == nil)
    }

    @Test func aDevelopmentBuildTakesAnyRelease() throws {
        #expect(UpdatePolicy.update(from: try release(), currentVersion: "dev") != nil)
        #expect(UpdatePolicy.update(from: try release(), currentVersion: "0.0.0") != nil)
    }

    @Test func ignoresDraftsAndPrereleases() throws {
        #expect(UpdatePolicy.update(from: try release(draft: true), currentVersion: "0.1.0") == nil)
        #expect(UpdatePolicy.update(from: try release(prerelease: true), currentVersion: "0.1.0") == nil)
    }

    @Test func needsTheZipOfThatVersion() throws {
        #expect(UpdatePolicy.update(from: try release(assets: ["Sixty-0.2.0.dmg"]), currentVersion: "0.1.0") == nil)
        #expect(UpdatePolicy.update(from: try release(assets: ["Sixty-0.1.9.zip"]), currentVersion: "0.1.0") == nil)
    }

    @Test func needsAnHTTPSGitHubURL() throws {
        let json = #"{"tag_name":"v0.2.0","draft":false,"prerelease":false,"assets":[{"name":"Sixty-0.2.0.zip","browser_download_url":"http://evil.example/Sixty-0.2.0.zip"}]}"#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(UpdatePolicy.update(from: release, currentVersion: "0.1.0") == nil)
    }

    @Test func checkSchedule() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(UpdatePolicy.isCheckDue(next: nil, now: now))
        let next = UpdatePolicy.nextCheck(after: now, succeeded: true)
        #expect(next == now.addingTimeInterval(12 * 3600))
        #expect(!UpdatePolicy.isCheckDue(next: next, now: now.addingTimeInterval(3600)))
        #expect(UpdatePolicy.isCheckDue(next: next, now: next))
        #expect(UpdatePolicy.nextCheck(after: now, succeeded: false) == now.addingTimeInterval(3600))
        // The clock jumped back by a day: do not wait a day and a half.
        #expect(UpdatePolicy.isCheckDue(next: next, now: now.addingTimeInterval(-86_400)))
    }

    @Test func installsOnlyBetweenBreaks() {
        let date = Date()
        #expect(UpdatePolicy.canInstall(during: .working))
        #expect(!UpdatePolicy.canInstall(during: .warning(endsAt: date)))
        #expect(!UpdatePolicy.canInstall(during: .onBreak(endsAt: date)))
        #expect(!UpdatePolicy.canInstall(during: .postponed(callEndedAt: nil)))
    }
}
