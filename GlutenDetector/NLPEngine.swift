//
//  NLPEngine.swift
//  GlutenDetector
//
//  A small NLP pipeline written from scratch (no NaturalLanguage framework,
//  no external NLP library). It sits AFTER the OCR and makes the keyword
//  search tolerant to the kind of mistakes OCR makes on small label print.
//
//  Pipeline:  text -> Tokenizer -> OCRNoise (repair variants)
//                  -> Stemmer (suffix stripping)
//                  -> EditDistance (fuzzy match against the gluten lexicon)
//
//  This is classical, rule-based NLP: it does not "learn" from data.
//

import Foundation

// MARK: - 1. Tokenizer

struct NLPToken {
    let text: String      // exactly as printed on the label
    let lower: String
    let range: NSRange    // position in the original text (for highlighting)
}

enum Tokenizer {
    /// Splits text into words made of letters/digits (A-Z, a-z, 0-9).
    /// Written as a manual scan over UTF-16 units so ranges stay correct.
    static func tokenize(_ text: String) -> [NLPToken] {
        let ns = text as NSString
        let units = Array(text.utf16)
        var tokens: [NLPToken] = []
        var start = -1

        for i in 0...units.count {                  // one step past the end flushes the last word
            let inWord = i < units.count && isWordUnit(units[i])
            if inWord {
                if start < 0 { start = i }
            } else if start >= 0 {
                let range = NSRange(location: start, length: i - start)
                let word = ns.substring(with: range)
                tokens.append(NLPToken(text: word, lower: word.lowercased(), range: range))
                start = -1
            }
        }
        return tokens
    }

    private static func isWordUnit(_ u: UInt16) -> Bool {
        (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || (u >= 48 && u <= 57)
    }
}

// MARK: - 2. OCR noise repair

enum OCRNoise {
    /// The original word first, then versions with the most common OCR
    /// confusions undone ("vvheat" -> "wheat", "rnalt" -> "malt", "wh3at" -> "wheat").
    static func variants(of lower: String) -> [String] {
        var out: [String] = [lower]
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }

        let hasDigit = lower.contains { $0.isNumber }
        let hasLetter = lower.contains { $0.isLetter }
        if hasDigit && hasLetter {
            let map: [Character: Character] = ["0": "o", "1": "l", "3": "e", "4": "a", "5": "s", "8": "b"]
            add(String(lower.map { map[$0] ?? $0 }))
        }
        add(lower.replacingOccurrences(of: "rn", with: "m"))
        add(lower.replacingOccurrences(of: "vv", with: "w"))
        return out
    }
}

// MARK: - 3. Stemmer (simple suffix stripping)

enum Stemmer {
    private static let suffixes = ["ings", "ing", "ed", "en", "es", "s"]

    /// "malted" -> "malt", "wheaten" -> "wheat", "barleys" -> "barley".
    static func stem(_ word: String) -> String {
        guard word.count > 4 else { return word }
        for suffix in suffixes where word.hasSuffix(suffix) {
            if word.count - suffix.count >= 3 {
                return String(word.dropLast(suffix.count))
            }
        }
        return word
    }
}

// MARK: - 4. Edit distance (Damerau-Levenshtein, "optimal string alignment")

enum EditDistance {
    /// Number of insertions / deletions / substitutions / swaps of adjacent
    /// letters needed to turn `s` into `t`. Returns limit+1 early if the
    /// words are obviously too different in length.
    static func distance(_ s: String, _ t: String, limit: Int) -> Int {
        let a = Array(s.utf8)
        let b = Array(t.utf8)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1,          // deletion
                              d[i][j - 1] + 1,          // insertion
                              d[i - 1][j - 1] + cost)   // substitution
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)   // swapped letters
                }
            }
        }
        return d[a.count][b.count]
    }
}

// MARK: - 5. The engine that ties it together

enum NLPEngine {

    /// Single-word gluten terms (multi-word terms are handled by the regex rules).
    private static let lexicon: [String] = GlutenKeywords.definite.filter {
        !$0.contains(" ") && !$0.contains("-") && !$0.contains("'")
    }
    private static let lexiconSet = Set(lexicon)

    /// Ordinary words that are one typo away from a gluten term. Never flag them.
    private static let benign: Set<String> = [
        "what", "heat", "cheat", "wheal", "whet",   // ~ wheat
        "barely",                                    // ~ barley
        "spell", "smelt", "spent", "spilt",          // ~ spelt
        "drum",                                      // ~ durum
        "marina",                                    // ~ farina
        "faro",                                      // ~ farro
        "scale"                                      // ~ secale
    ]

    /// Finds gluten words the exact-match rules missed:
    ///  - inflected forms ("malted", "wheaten")        -> .definite
    ///  - OCR-damaged or misspelled words ("whaat")     -> .caution, with a suggestion
    static func extraMatches(in text: String, skipping covered: [NSRange]) -> [GlutenMatch] {
        var results: [GlutenMatch] = []
        for token in Tokenizer.tokenize(text) {
            guard token.lower.count >= 5 else { continue }      // short words: too risky to guess
            if covered.contains(where: { NSIntersectionRange($0, token.range).length > 0 }) { continue }
            if let match = classify(token) { results.append(match) }
        }
        return results
    }

    private static func classify(_ token: NLPToken) -> GlutenMatch? {
        let variants = OCRNoise.variants(of: token.lower)

        for (index, variant) in variants.enumerated() {
            let repaired = index > 0        // variants[0] is the word as printed
            if benign.contains(variant) { continue }

            // Exact lexicon word.
            if lexiconSet.contains(variant) {
                if repaired {
                    return GlutenMatch(term: token.text, range: token.range,
                                       severity: .caution, suggestion: variant)
                }
                continue    // exact word as printed: the regex rules already decided (e.g. "wheat-free")
            }

            // Same word with a different ending.
            if !repaired {
                let stem = Stemmer.stem(variant)
                if stem != variant, lexiconSet.contains(stem) {
                    return GlutenMatch(term: token.text, range: token.range,
                                       severity: .definite, suggestion: nil)
                }
            }

            // Close to a gluten word (typo / OCR error).
            for word in lexicon where word.count >= 5 {
                let limit = word.count >= 8 ? 2 : 1
                if EditDistance.distance(variant, word, limit: limit) <= limit {
                    return GlutenMatch(term: token.text, range: token.range,
                                       severity: .caution, suggestion: word)
                }
            }
        }
        return nil
    }
}
