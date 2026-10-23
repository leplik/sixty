import Testing
@testable import SixtyCore

/// Deterministic generator for repeatable tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("EscapePhrase")
struct EscapePhraseTests {
    @Test func makesFourDistinctKnownWords() {
        var rng = SeededGenerator(state: 42)
        for _ in 0..<200 {
            let words = EscapePhrase.make(using: &rng).split(separator: " ").map(String.init)
            #expect(words.count == 4)
            #expect(Set(words).count == 4)
            #expect(words.allSatisfy { EscapePhrase.words.contains($0) })
        }
    }

    @Test func phrasesChange() {
        var rng = SeededGenerator(state: 7)
        let phrases = Set((0..<50).map { _ in EscapePhrase.make(using: &rng) })
        #expect(phrases.count > 45)
    }

    @Test func wordListIsCleanLowercaseLatin() {
        #expect(EscapePhrase.words.count >= 100)
        #expect(Set(EscapePhrase.words).count == EscapePhrase.words.count)
        for word in EscapePhrase.words {
            #expect(word.allSatisfy { ("a"..."z").contains($0) }, "\(word)")
            #expect((4...8).contains(word.count), "\(word)")
        }
    }

    @Test func matchIgnoresCaseAndSpacing() {
        #expect(EscapePhrase.matches("  River   CANDLE orbit maple ", "river candle orbit maple"))
    }

    @Test func wrongOrIncompleteInputDoesNotMatch() {
        #expect(!EscapePhrase.matches("river candle orbit", "river candle orbit maple"))
        #expect(!EscapePhrase.matches("candle river orbit maple", "river candle orbit maple"))
        #expect(!EscapePhrase.matches("", "river candle orbit maple"))
    }

    @Test func russianLayoutTypingMatchesByKeyPosition() {
        // "river candle" typed with the Russian ЙЦУКЕН layout active.
        #expect(EscapePhrase.matches("кшмук сфтвду", "river candle"))
        #expect(EscapePhrase.matches("КШМУК СФТВДУ", "river candle"))
    }

    @Test func belarusianAndUkrainianLettersMap() {
        // "is" → Belarusian/Ukrainian "і" sits on the S key, "ў" on the O key.
        #expect(EscapePhrase.normalize("ш і") == "i s")
        #expect(EscapePhrase.normalize("ў") == "o")
    }
}
