import AppKit
import SwiftUI

/// Localised UI text. Keys are the English strings; `ru.lproj/Localizable.strings` holds Russian.
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
