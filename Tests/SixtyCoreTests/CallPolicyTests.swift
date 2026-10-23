import Testing
@testable import SixtyCore

@Suite("CallPolicy")
struct CallPolicyTests {
    private let policy = CallPolicy.standard

    private func mic(_ id: String) -> AudioClient {
        AudioClient(bundleID: id, usesMicrophone: true, usesSpeaker: false)
    }

    private func speaker(_ id: String) -> AudioClient {
        AudioClient(bundleID: id, usesMicrophone: false, usesSpeaker: true)
    }

    @Test func nothingInUseIsNoCall() {
        #expect(policy.signal(for: DeviceSnapshot(audioClients: [], cameraInUse: false)) == nil)
    }

    @Test func cameraAloneIsACall() {
        #expect(policy.signal(for: DeviceSnapshot(audioClients: [], cameraInUse: true)) == .camera)
    }

    @Test func browserHelperOnTheMicrophoneIsACall() {
        let s = DeviceSnapshot(audioClients: [mic("com.google.Chrome.helper")], cameraInUse: false)
        #expect(policy.signal(for: s) == .microphone(app: "Google Chrome"))
    }

    @Test(arguments: [
        ("com.tdesktop.Telegram", "Telegram"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.microsoft.teams2", "Microsoft Teams"),
        ("com.microsoft.teams2.helper", "Microsoft Teams"),
        ("us.zoom.xos", "Zoom"),
        ("com.apple.WebKit.GPU", "Safari"),
        ("company.thebrowser.Browser.helper", "Arc"),
    ])
    func knownAppsOnTheMicrophone(id: String, name: String) {
        let s = DeviceSnapshot(audioClients: [mic(id)], cameraInUse: false)
        #expect(policy.signal(for: s) == .microphone(app: name))
    }

    @Test(arguments: ["com.pais.handy", "com.obsproject.obs-studio", "com.apple.CoreSpeech", ""])
    func dictationAndRecordersAreIgnored(id: String) {
        let s = DeviceSnapshot(audioClients: [mic(id)], cameraInUse: false)
        #expect(policy.signal(for: s) == nil)
    }

    @Test func matchingIgnoresCase() {
        let s = DeviceSnapshot(audioClients: [mic("COM.GOOGLE.CHROME")], cameraInUse: false)
        #expect(policy.signal(for: s) == .microphone(app: "Google Chrome"))
    }

    @Test func aPrefixMustEndAtADot() {
        let s = DeviceSnapshot(audioClients: [mic("com.google.Chromecast")], cameraInUse: false)
        #expect(policy.signal(for: s) == nil)
    }

    @Test func speakerCountsOnlyForMeetingApps() {
        let teams = DeviceSnapshot(audioClients: [speaker("com.microsoft.teams2")], cameraInUse: false)
        #expect(policy.signal(for: teams) == .speaker(app: "Microsoft Teams"))

        let chrome = DeviceSnapshot(audioClients: [speaker("com.google.Chrome.helper")], cameraInUse: false)
        #expect(policy.signal(for: chrome) == nil)

        let telegram = DeviceSnapshot(audioClients: [speaker("com.tdesktop.Telegram")], cameraInUse: false)
        #expect(policy.signal(for: telegram) == nil)
    }

    @Test func microphoneWinsOverSpeaker() {
        let s = DeviceSnapshot(
            audioClients: [speaker("us.zoom.xos"), mic("com.tdesktop.Telegram")],
            cameraInUse: false
        )
        #expect(policy.signal(for: s) == .microphone(app: "Telegram"))
    }

    @Test func everyAppHasANameAndIDs() {
        for app in policy.apps {
            #expect(!app.name.isEmpty)
            #expect(!app.bundleIDs.isEmpty)
        }
    }
}
