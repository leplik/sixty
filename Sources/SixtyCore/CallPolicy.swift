import Foundation

/// One process that currently uses an audio device, as CoreAudio reports it.
public struct AudioClient: Equatable, Sendable {
    public var bundleID: String
    public var usesMicrophone: Bool
    public var usesSpeaker: Bool

    public init(bundleID: String, usesMicrophone: Bool, usesSpeaker: Bool) {
        self.bundleID = bundleID
        self.usesMicrophone = usesMicrophone
        self.usesSpeaker = usesSpeaker
    }
}

/// Device usage at one moment.
public struct DeviceSnapshot: Equatable, Sendable {
    public var audioClients: [AudioClient]
    public var cameraInUse: Bool

    public init(audioClients: [AudioClient], cameraInUse: Bool) {
        self.audioClients = audioClients
        self.cameraInUse = cameraInUse
    }
}

/// Why Sixty thinks a call is active. The menu shows it, so a stuck signal is visible.
public enum CallSignal: Equatable, Sendable {
    case camera
    case microphone(app: String)
    case speaker(app: String)
}

/// An app that makes calls.
public struct CallApp: Equatable, Sendable {
    public var name: String
    /// A process matches if its bundle ID equals one of these or starts with one plus a dot.
    public var bundleIDs: [String]
    /// If `true`, audio output alone means a call (dedicated meeting apps only).
    public var speakerMeansCall: Bool

    public init(name: String, bundleIDs: [String], speakerMeansCall: Bool = false) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.speakerMeansCall = speakerMeansCall
    }

    public func matches(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return bundleIDs.contains { known in
            let known = known.lowercased()
            return id == known || id.hasPrefix(known + ".")
        }
    }
}

/// Decides from a `DeviceSnapshot` whether a call is active. See docs/SPEC.md, section 4.
public struct CallPolicy: Sendable {
    public var apps: [CallApp]

    public init(apps: [CallApp]) {
        self.apps = apps
    }

    public func signal(for snapshot: DeviceSnapshot) -> CallSignal? {
        if snapshot.cameraInUse { return .camera }
        for client in snapshot.audioClients where client.usesMicrophone {
            if let app = app(for: client.bundleID) { return .microphone(app: app.name) }
        }
        for client in snapshot.audioClients where client.usesSpeaker {
            if let app = app(for: client.bundleID), app.speakerMeansCall { return .speaker(app: app.name) }
        }
        return nil
    }

    private func app(for bundleID: String) -> CallApp? {
        apps.first { $0.matches(bundleID) }
    }

    public static let standard = CallPolicy(apps: [
        // Browsers: Google Meet, Jitsi, Whereby and any other call in a tab.
        CallApp(name: "Google Chrome", bundleIDs: ["com.google.Chrome"]),
        CallApp(name: "Arc", bundleIDs: ["company.thebrowser.Browser"]),
        CallApp(name: "Dia", bundleIDs: ["company.thebrowser.dia"]),
        CallApp(name: "Safari", bundleIDs: ["com.apple.Safari", "com.apple.WebKit.GPU"]),
        CallApp(name: "Microsoft Edge", bundleIDs: ["com.microsoft.edgemac"]),
        CallApp(name: "Brave", bundleIDs: ["com.brave.Browser"]),
        CallApp(name: "Firefox", bundleIDs: ["org.mozilla.firefox", "org.mozilla.plugincontainer"]),
        CallApp(name: "Vivaldi", bundleIDs: ["com.vivaldi.Vivaldi"]),
        CallApp(name: "Opera", bundleIDs: ["com.operasoftware.Opera"]),
        // Meeting apps: audio output alone also means a call (microphone muted).
        CallApp(name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams", "com.microsoft.teams2"], speakerMeansCall: true),
        CallApp(name: "Zoom", bundleIDs: ["us.zoom.xos"], speakerMeansCall: true),
        CallApp(name: "Webex", bundleIDs: ["Cisco-Systems.Spark", "com.webex.meetingmanager"], speakerMeansCall: true),
        CallApp(
            name: "FaceTime",
            bundleIDs: ["com.apple.FaceTime", "com.apple.avconferenced", "com.apple.TelephonyUtilities"],
            speakerMeansCall: true
        ),
        // Messengers: they also play videos and notification sounds, so only the microphone counts.
        CallApp(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"]),
        CallApp(name: "Telegram", bundleIDs: ["com.tdesktop.Telegram", "ru.keepcoder.Telegram"]),
        CallApp(name: "WhatsApp", bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        CallApp(name: "Discord", bundleIDs: ["com.hnc.Discord"]),
        CallApp(name: "Signal", bundleIDs: ["org.whispersystems.signal-desktop"]),
        CallApp(name: "Viber", bundleIDs: ["com.viber.osx"]),
        CallApp(name: "Skype", bundleIDs: ["com.skype.skype"]),
        // Meeting recorders record only during a call.
        CallApp(name: "Granola", bundleIDs: ["com.granola.app"]),
    ])
}
