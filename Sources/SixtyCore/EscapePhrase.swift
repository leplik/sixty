import Foundation

/// The emergency exit from a break: 4 random words, new every time, so they cannot be typed on autopilot.
public enum EscapePhrase {
    public static let wordCount = 4

    public static func make<R: RandomNumberGenerator>(using rng: inout R) -> String {
        var pool = words
        var picked: [String] = []
        for _ in 0..<wordCount {
            picked.append(pool.remove(at: Int.random(in: 0..<pool.count, using: &rng)))
        }
        return picked.joined(separator: " ")
    }

    public static func make() -> String {
        var rng = SystemRandomNumberGenerator()
        return make(using: &rng)
    }

    /// Ignores case and extra spaces. Cyrillic letters count as the Latin key at the same position,
    /// so a phrase typed with a Russian, Ukrainian or Belarusian layout still matches.
    public static func matches(_ typed: String, _ phrase: String) -> Bool {
        let typed = normalize(typed)
        return !typed.isEmpty && typed == normalize(phrase)
    }

    static func normalize(_ text: String) -> String {
        let latin = String(text.lowercased().map { keyPosition[$0] ?? $0 })
        return latin.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// ЙЦУКЕН → QWERTY for the letter keys.
    private static let keyPosition: [Character: Character] = {
        var map = Dictionary(uniqueKeysWithValues: zip("йцукенгшщзфывапролдячсмить", "qwertyuiopasdfghjklzxcvbnm"))
        map["і"] = "s" // Ukrainian and Belarusian, on the Russian "ы" key
        map["ў"] = "o" // Belarusian, on the Russian "щ" key
        return map
    }()

    /// Short, common, unambiguous English words. Lowercase a–z only, 4–8 letters.
    public static let words: [String] = [
        "anchor", "apple", "bamboo", "banana", "basket", "bridge", "butter", "cactus", "candle", "canyon",
        "carpet", "castle", "cherry", "cloud", "comet", "cookie", "copper", "coral", "cotton", "daisy",
        "desert", "dragon", "eagle", "ember", "engine", "fabric", "falcon", "feather", "forest", "fossil",
        "galaxy", "garden", "ginger", "glacier", "guitar", "hammer", "harbor", "helmet", "hockey", "honey",
        "igloo", "insect", "island", "ivory", "jacket", "jelly", "jigsaw", "jungle", "kayak", "kettle",
        "kitten", "koala", "ladder", "lantern", "lemon", "lizard", "lobster", "magnet", "mango", "maple",
        "marble", "meadow", "mirror", "muffin", "napkin", "nectar", "needle", "noodle", "nutmeg", "ocean",
        "olive", "orange", "orbit", "otter", "oyster", "paddle", "panda", "parrot", "peanut", "pebble",
        "pencil", "pepper", "piano", "pirate", "planet", "pocket", "poodle", "pretzel", "puzzle", "rabbit",
        "radar", "raven", "rhythm", "ribbon", "river", "robot", "rocket", "saddle", "salmon", "saturn",
        "scooter", "shadow", "silver", "spider", "sponge", "spring", "stereo", "stone", "string", "sugar",
        "summer", "sunset", "thunder", "ticket", "tiger", "tomato", "tractor", "travel", "trumpet", "tulip",
        "tunnel", "turtle", "valley", "vanilla", "velvet", "violet", "volcano", "wagon", "wallet", "walnut",
        "walrus", "whistle", "window", "winter", "wizard", "yellow", "yogurt", "zebra", "zipper",
    ]
}
