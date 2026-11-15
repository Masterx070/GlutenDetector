//
//  ArabicNLP.swift
//  GlutenDetector
//
//  Arabic text analysis written from scratch (no external NLP library).
//  Arabic needs extra care compared with English:
//    1. Normalisation  - remove diacritics/tatweel, unify alef/yaa/taa-marbuta forms
//    2. Prefix/suffix stripping - "بالقمح" (with the wheat) -> "قمح"
//    3. Dot-insensitive matching - OCR often drops dots: "قمح" read as "فمح"
//    4. Context - "may contain", "gluten free", "without" in Arabic
//
//  Classical rule-based NLP: it does not learn from data.
//

import Foundation

enum ArabicNLP {

    // MARK: - 1. Normalisation

    private static let charMap: [UInt32: UInt32] = [
        0x0623: 0x0627, 0x0625: 0x0627, 0x0622: 0x0627, 0x0671: 0x0627,   // أ إ آ ٱ -> ا
        0x0649: 0x064A,                                                    // ى -> ي
        0x0629: 0x0647,                                                    // ة -> ه
        0x06A9: 0x0643, 0x06CC: 0x064A                                     // Persian kaf / yaa -> Arabic
    ]

    static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x064B...0x065F).contains(v) || v == 0x0670 || v == 0x0640 { continue }   // diacritics, tatweel
            if let mapped = charMap[v], let m = Unicode.Scalar(mapped) {
                out.append(m)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// Letters that differ only by dots are collapsed (OCR often loses the dots).
    private static let skeletonMap: [Character: Character] = [
        "ت": "ب", "ث": "ب", "ن": "ب", "ي": "ب",
        "خ": "ج", "ح": "ج", "ذ": "د", "ز": "ر", "ش": "س",
        "ض": "ص", "ظ": "ط", "غ": "ع", "ق": "ف"
    ]

    static func skeleton(_ s: String) -> String {
        String(s.map { skeletonMap[$0] ?? $0 })
    }

    // MARK: - 2. Tokenizer

    private struct ArabicToken {
        let original: String
        let norm: String
        let range: NSRange
        let endsSentence: Bool     // a . ; or ؛ follows this word
    }

    private static func isArabicUnit(_ u: UInt16) -> Bool {
        (0x0621...0x065F).contains(u) || u == 0x0670 || (0x0671...0x06D3).contains(u) || u == 0x066E || u == 0x066F
    }

    private static func tokenize(_ text: String) -> [ArabicToken] {
        let ns = text as NSString
        let units = Array(text.utf16)

        var ranges: [NSRange] = []
        var start = -1
        for i in 0...units.count {
            let inWord = i < units.count && isArabicUnit(units[i])
            if inWord {
                if start < 0 { start = i }
            } else if start >= 0 {
                ranges.append(NSRange(location: start, length: i - start))
                start = -1
            }
        }

        var tokens: [ArabicToken] = []
        for (k, r) in ranges.enumerated() {
            let original = ns.substring(with: r)
            let norm = normalize(original)
            guard !norm.isEmpty else { continue }

            let gapStart = r.location + r.length
            let gapEnd = (k + 1 < ranges.count) ? ranges[k + 1].location : units.count
            var ends = false
            if gapStart < gapEnd {
                for u in units[gapStart..<gapEnd] where u == 0x2E || u == 0x3B || u == 0x061B { ends = true }
            }
            tokens.append(ArabicToken(original: original, norm: norm, range: r, endsSentence: ends))
        }
        return tokens
    }

    // MARK: - 3. Light stemmer (prefix / suffix stripping)

    private static let prefixes = ["وبال", "فبال", "وكال", "ولل", "وال", "فال", "بال", "كال",
                                   "لل", "ال", "و", "ف", "ب", "ك", "ل"]
    private static let suffixes = ["ات", "ان", "ين", "ون", "ها", "ه", "ي"]

    /// The word itself plus versions with a prefix and/or suffix removed.
    private static func candidates(of w: String) -> [String] {
        var stems = [w]
        for p in prefixes where w.hasPrefix(p) && w.count - p.count >= 3 {
            stems.append(String(w.dropFirst(p.count)))
        }
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        for stem in stems {
            add(stem)
            for s in suffixes where stem.hasSuffix(s) && stem.count - s.count >= 3 {
                add(String(stem.dropLast(s.count)))
            }
        }
        return out
    }

    // MARK: - Lexicon (normalised once)

    private struct Rule {
        let words: [String]
        let severity: MatchSeverity
        let display: String
    }

    private static let rules: [Rule] = {
        let all = GlutenKeywords.arabicDefinite.map { ($0, MatchSeverity.definite) }
                + GlutenKeywords.arabicCaution.map { ($0, MatchSeverity.caution) }
        return all.map { term, severity -> Rule in
            let words = normalize(term).split(separator: " ").map(String.init)
            return Rule(words: words, severity: severity, display: term)
        }
    }()

    private static func normalizedSet(_ list: [String]) -> Set<String> { Set(list.map(normalize)) }

    private static let flourWords = normalizedSet(["دقيق", "طحين"])
    private static let safeFlour = normalizedSet(GlutenKeywords.arabicSafeFlourQualifiers)
    private static let negSingle = normalizedSet(GlutenKeywords.arabicNegationSingle)
    private static let negFree = normalizedSet(GlutenKeywords.arabicNegationFree)
    private static let headers = normalizedSet(GlutenKeywords.arabicIngredientHeaders)
    private static let advisoryPhrases: [[String]] = GlutenKeywords.arabicAdvisoryPhrases.map {
        normalize($0).split(separator: " ").map(String.init)
    }
    /// Real words that look like a gluten word once dots are ignored.
    private static let benign: Set<String> = ["سعير"]
    /// Ordinary words that must never match (their stem equals a gluten word).
    private static let excluded: Set<String> = [normalize("طحينة")]
    private static let shortFuzzyAllowed = "قمح"

    // MARK: - 4. Matching

    private enum Hit { case exact, fuzzy }

    private static func hit(_ cands: [String], word: String) -> Hit? {
        if cands.contains(word) { return .exact }
        if word.count >= 4 || word == shortFuzzyAllowed {
            let target = skeleton(word)
            for c in cands where c.count >= 3 && !benign.contains(c) && skeleton(c) == target {
                return .fuzzy
            }
        }
        return nil
    }

    private static func tokenIs(_ token: ArabicToken, in set: Set<String>) -> Bool {
        candidates(of: token.norm).contains { set.contains($0) }
    }

    /// Finds Arabic gluten terms. Ranges refer to the ORIGINAL text, so highlighting works.
    static func findMatches(in text: String) -> [GlutenMatch] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }
        let ns = text as NSString
        let advisory = advisoryFlags(tokens)
        // Words that merely look like a gluten word after stemming (tahini = sesame paste).
        let cands = tokens.map { excluded.contains($0.norm) ? [] : candidates(of: $0.norm) }

        var matches: [GlutenMatch] = []
        for rule in rules {
            let n = rule.words.count
            if tokens.count < n { continue }

            for i in 0...(tokens.count - n) {
                var allExact = true
                var anyFuzzy = false
                var valid = true
                for j in 0..<n {
                    guard let h = hit(cands[i + j], word: rule.words[j]) else { valid = false; break }
                    if h == .fuzzy { anyFuzzy = true; allExact = false }
                }
                guard valid else { continue }
                if anyFuzzy && n > 1 { continue }            // fuzzy only for single words

                if isNegated(tokens, at: i) { continue }
                if rule.words.count == 1, flourWords.contains(rule.words[0]),
                   i + 1 < tokens.count, tokenIs(tokens[i + 1], in: safeFlour) { continue }

                let first = tokens[i].range
                let last = tokens[i + n - 1].range
                let range = NSRange(location: first.location,
                                    length: last.location + last.length - first.location)
                let term = ns.substring(with: range)

                var severity = rule.severity
                var suggestion: String? = nil
                if anyFuzzy {
                    severity = .caution                       // OCR-damaged word: never "definite"
                    suggestion = rule.display
                } else if allExact, advisory[i], severity == .definite {
                    severity = .advisory
                }
                matches.append(GlutenMatch(term: term, range: range, severity: severity, suggestion: suggestion))
            }
        }
        return matches
    }

    /// Is there an ingredients-list heading ("المكونات") in the text?
    static func hasIngredientsHeader(in text: String) -> Bool {
        tokenize(text).contains { tokenIs($0, in: headers) }
    }

    // MARK: - 5. Context

    /// "بدون X", "خالٍ من X", "لا يحتوي على X" => X is being denied, not listed.
    private static func isNegated(_ tokens: [ArabicToken], at i: Int) -> Bool {
        guard i >= 1 else { return false }
        let prev1 = tokens[i - 1]
        if tokenIs(prev1, in: negSingle) { return true }

        let from = normalizedSet(["من"])
        if i >= 2, tokenIs(prev1, in: from), tokenIs(tokens[i - 2], in: negFree) { return true }

        let onWord = normalizedSet(["على"])
        let contains = normalizedSet(["يحتوي", "تحتوي", "لايحتوي", "لاتحتوي"])
        if i >= 3, tokenIs(prev1, in: onWord), tokenIs(tokens[i - 2], in: contains),
           tokens[i - 3].norm == "لا" { return true }
        if i >= 2, tokenIs(prev1, in: onWord),
           tokenIs(tokens[i - 2], in: normalizedSet(["لايحتوي", "لاتحتوي"])) { return true }
        return false
    }

    /// Marks the words that follow a "may contain / traces / shared facility" phrase
    /// (up to 12 words, or until the sentence ends).
    private static func advisoryFlags(_ tokens: [ArabicToken]) -> [Bool] {
        var flags = Array(repeating: false, count: tokens.count)
        var remaining = 0
        for i in 0..<tokens.count {
            if remaining > 0 {
                flags[i] = true
                remaining -= 1
                if tokens[i].endsSentence { remaining = 0 }
            }
            if !tokens[i].endsSentence && startsAdvisory(tokens, at: i) { remaining = 12 }
        }
        return flags
    }

    private static func startsAdvisory(_ tokens: [ArabicToken], at i: Int) -> Bool {
        for phrase in advisoryPhrases {
            if i + phrase.count > tokens.count { continue }
            var ok = true
            for (j, word) in phrase.enumerated() {
                if !candidates(of: tokens[i + j].norm).contains(word) { ok = false; break }
            }
            if ok { return true }
        }
        return false
    }
}
