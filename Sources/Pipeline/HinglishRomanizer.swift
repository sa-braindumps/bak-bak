import Foundation

/// Turns Devanagari into the Roman-letter Hindi people actually type
/// ("कल मीटिंग है" → "kal meeting hai").
///
/// The transcription models always write Hindi speech in Devanagari, whatever
/// the prompt says, so Hinglish mode converts afterwards. This is
/// deterministic, with no model call:
///
/// 1. Drop the silent "a" that Hindi speakers don't pronounce: at the end of a
///    word ("कल" kal, not kala) and in the middle where the usual rule says so
///    ("करता" karta, not karata).
/// 2. Transliterate with the system's ICU Devanagari → Latin transform.
/// 3. Map scholarly spellings to everyday ones (ī → ee, ś → sh, word-final
///    ee → i) and strip the remaining accents.
/// 4. Fix common English loanwords ("riport" → "report").
///
/// Text that isn't Devanagari passes through untouched. The user's `[vocab]`
/// runs after this, so anything it gets wrong can be taught like any other
/// mishearing.
public enum HinglishRomanizer {

    public static func romanize(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isDevanagari) else { return text }

        var latin = deleteSilentSchwas(text).applyingTransform(.toLatin, reverse: false) ?? text
        for (from, to) in spellingMap {
            latin = latin.replacingOccurrences(of: from, with: to)
        }
        latin = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        latin = latin
            .replacingOccurrences(of: "\u{0964}", with: ".")   // ।
            .replacingOccurrences(of: "\u{0965}", with: ".")   // ॥
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "ee\\b", with: "i", options: .regularExpression)
        return Substitutor.apply(latin, vocab: loanwords)
    }

    // MARK: - Spelling

    /// ICU's output is scholarly (ISO 15919); this is how people type it.
    private static let spellingMap: [(String, String)] = [
        ("m\u{0310}", "n"),            // chandrabindu: hūm̐ → hoon
        ("r\u{0325}", "ri"),           // kr̥payā → kripaya
        ("ā", "a"), ("ī", "ee"), ("ū", "oo"), ("ē", "e"), ("ō", "o"), ("ŏ", "o"), ("ê", "e"), ("ô", "o"),
        ("ṅ", "n"), ("ñ", "n"), ("ṇ", "n"), ("ṁ", "n"),
        ("ś", "sh"), ("ṣ", "sh"), ("ṭ", "t"), ("ḍ", "d"), ("ṛ", "r"), ("ḥ", "h"),
    ]

    /// A few common English words as they come out of step 3. Deliberately
    /// short: anything else is taught through `[vocab]` like any mishearing.
    public static let loanwords: [String: String] = [
        "riport": "report", "phiks": "fix", "ishyoo": "issue", "pleez": "please",
        "redi": "ready", "klaint": "client", "kol": "call", "dek": "deck",
        "diployment": "deployment", "ofis": "office", "maisej": "message",
    ]

    // MARK: - Silent schwa

    private enum Vowel { case inherent, sign, none }

    private struct Akshara {
        var scalars: [Unicode.Scalar]
        var isConsonant: Bool
        var vowel: Vowel
        /// Anusvara, chandrabindu or visarga after an inherent vowel keeps it.
        var hasNasalOrVisarga = false
    }

    private static func isDevanagari(_ u: Unicode.Scalar) -> Bool { (0x0900...0x097F).contains(u.value) }
    private static func isConsonant(_ u: Unicode.Scalar) -> Bool {
        (0x0915...0x0939).contains(u.value) || (0x0958...0x095F).contains(u.value)
    }
    private static func isVowelSign(_ u: Unicode.Scalar) -> Bool {
        (0x093E...0x094C).contains(u.value) || (0x0962...0x0963).contains(u.value)
    }
    private static let nukta: Unicode.Scalar = "\u{093C}"
    private static let virama: Unicode.Scalar = "\u{094D}"

    /// Rewrites each Devanagari word so ICU won't voice the schwas a Hindi
    /// speaker drops, by adding a virama after those consonants.
    static func deleteSilentSchwas(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var word: [Unicode.Scalar] = []

        func flush() {
            out.append(contentsOf: rewrite(word))
            word.removeAll()
        }

        for scalar in text.unicodeScalars {
            if isDevanagari(scalar) && scalar.value != 0x0964 && scalar.value != 0x0965 {
                word.append(scalar)
            } else {
                flush()
                out.append(scalar)
            }
        }
        flush()
        return String(out)
    }

    private static func rewrite(_ word: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var units = aksharas(word)
        guard units.count >= 2 else { return word }

        func keepsVowel(_ i: Int) -> Bool {
            units[i].vowel == .sign || units[i].vowel == .inherent || !units[i].isConsonant
        }
        func deletable(_ i: Int) -> Bool {
            units[i].isConsonant && units[i].vowel == .inherent && !units[i].hasNasalOrVisarga
        }

        // Word-final: "कल" → kal.
        let last = units.count - 1
        if deletable(last) { units[last].vowel = .none; units[last].scalars.append(virama) }

        // Medial (Ohala's rule, simplified): V C[a] C V → V C C V. Left to
        // right, never two in a row, never the first syllable.
        var i = 1
        while i < last {
            if deletable(i),
               keepsVowel(i - 1), units[i - 1].vowel != .none,
               units[i + 1].isConsonant, units[i + 1].vowel != .none {
                units[i].vowel = .none
                units[i].scalars.append(virama)
                i += 2
            } else {
                i += 1
            }
        }
        return units.flatMap(\.scalars)
    }

    /// Split a word into aksharas: a consonant (+ nukta) with its vowel sign,
    /// virama, or inherent vowel; or an independent vowel.
    private static func aksharas(_ word: [Unicode.Scalar]) -> [Akshara] {
        var units: [Akshara] = []
        for scalar in word {
            if isConsonant(scalar) {
                units.append(Akshara(scalars: [scalar], isConsonant: true, vowel: .inherent))
            } else if var current = units.popLast() {
                current.scalars.append(scalar)
                if scalar == virama {
                    current.vowel = .none
                } else if isVowelSign(scalar), current.isConsonant {
                    current.vowel = .sign
                } else if scalar == nukta {
                    // part of the consonant
                } else if [0x0901, 0x0902, 0x0903].contains(scalar.value) {
                    current.hasNasalOrVisarga = true
                } else if !isVowelSign(scalar) {
                    // An independent vowel starts its own unit.
                    current.scalars.removeLast()
                    units.append(current)
                    units.append(Akshara(scalars: [scalar], isConsonant: false, vowel: .sign))
                    continue
                }
                units.append(current)
            } else {
                units.append(Akshara(scalars: [scalar], isConsonant: false, vowel: .sign))
            }
        }
        return units
    }
}
