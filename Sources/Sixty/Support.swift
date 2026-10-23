import AppKit
import os
import SwiftUI

/// Diagnostics in the macOS unified log. Read them with `Sixty --log`, or
/// `log show --predicate 'subsystem == "pro.saac.sixty"' --last 6h`.
/// Everything logged is public on purpose: phases, timings, app and exercise names. Never personal data.
enum Log {
    static let cycle = Logger(subsystem: "pro.saac.sixty", category: "cycle")
    static let calls = Logger(subsystem: "pro.saac.sixty", category: "calls")
    static let update = Logger(subsystem: "pro.saac.sixty", category: "update")
    static let agent = Logger(subsystem: "pro.saac.sixty", category: "agent")

    /// `Sixty --log`: the last 6 hours of Sixty's own log lines.
    static func show() -> Int32 {
        let log = Process()
        log.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        log.arguments = ["show", "--predicate", "subsystem == \"pro.saac.sixty\"", "--last", "6h", "--style", "compact"]
        guard (try? log.run()) != nil else { return 1 }
        log.waitUntilExit()
        return log.terminationStatus
    }
}

/// UI text. Sixty is English only; the key is the text. One function keeps every UI string easy to find.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum Links {
    static let website = URL(string: "https://leplik.github.io/sixty/")!
    static let turnOff = URL(string: "https://github.com/leplik/sixty#turning-sixty-off")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Shared with the website and the icon: dark base, one warm accent.
enum Palette {
    static let accent = Color(red: 1.0, green: 0.541, blue: 0.239) // #FF8A3D
    static let top = Color(red: 0.051, green: 0.071, blue: 0.098) // #0D1219
    static let bottom = Color(red: 0.020, green: 0.031, blue: 0.051) // #05080D
}
