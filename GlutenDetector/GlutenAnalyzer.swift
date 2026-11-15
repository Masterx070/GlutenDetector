//
//  GlutenAnalyzer.swift
//  GlutenDetector
//
//  Keyword matching on the OCR text (FR4, FR5, FR6), English + Arabic.
//  Labels in Saudi Arabia are often bilingual, so BOTH languages are
//  always checked, whatever language the app is displayed in.
//  Design rule for a health app: when in doubt, say "Uncertain" — never "safe".
//

import Foundation

enum MatchSeverity {
    case definite   // ingredient contains gluten
    case advisory   // "may contain traces of wheat"
    case caution    // ambiguous (e.g. oats) or a possibly misread word
}

struct GlutenMatch: Identifiable {
    let id = UUID()
    let term: String          // the text exactly as found on the label
    let range: NSRange        // position inside the extracted text (for highlighting)
    let severity: MatchSeverity
    var suggestion: String? = nil   // set by the NLP layers: "this looks like <suggestion>"
}

/// Why the app decided what it decided. Stored as a code + terms so the
/// sentence can be shown in whichever language the user picks later.
enum AnalysisReason {
    case found(String)
    case possible(String)
    case unclear
    case noIngredientsList
    case clean

    var code: String {
        switch self {
        case .found: return "found"
        case .possible: return "possible"
        case .unclear: return "unclear"
        case .noIngredientsList: return "noList"
        case .clean: return "clean"
        }
    }

    var terms: String {
        switch self {
        case .found(let t), .possible(let t): return t
        default: return ""
        }
    }

    init?(code: String, terms: String) {
        switch code {
        case "found": self = .found(terms)
        case "possible": self = .possible(terms)
        case "unclear": self = .unclear
        case "noList": self = .noIngredientsList
        case "clean": self = .clean
        default: return nil
        }
    }

    func text(_ lang: AppLanguage) -> String {
        let isAr = lang.isArabic
        switch self {
        case .found(let raw):
            let t = Self.format(raw, lang)
            return isAr ? "تم العثور على: \(t)." : "Found: \(t)."
        case .possible(let raw):
            let t = Self.format(raw, lang)
            return isAr ? "احتمال وجود غلوتين: \(t). تحقق من الملصق يدوياً."
                        : "Possible gluten risk: \(t). Check the label manually."
        case .unclear:
            return isAr ? "النص قصير أو غير واضح للحكم عليه. أعد التصوير عن قرب وبإضاءة جيدة."
                        : "The text is too short or unclear to judge. Retake the photo closer, in good light."
        case .noIngredientsList:
            return isAr ? "لم يتم العثور على قائمة المكونات. تأكد أن قسم المكونات ظاهر في الصورة."
                        : "No \"Ingredients\" list was found. Make sure the ingredients section is in the photo."
        case .clean:
            return isAr ? "لم يتم العثور على مكونات تحتوي على غلوتين في النص."
                        : "No gluten-containing ingredients were found in the text."
        }
    }

    /// "whaat→wheat; malt"  ->  "whaat (maybe “wheat”), malt"
    private static func format(_ raw: String, _ lang: AppLanguage) -> String {
        raw.components(separatedBy: "; ").map { item -> String in
            let parts = item.components(separatedBy: "→")
            if parts.count == 2 { return "\(parts[0]) (\(lang.t(.maybe)) “\(parts[1])”)" }
            return item
        }.joined(separator: lang.isArabic ? "، " : ", ")
    }
}

struct GlutenAnalysis {
    let result: GlutenResult
    let matches: [GlutenMatch]
    let reason: AnalysisReason
}

enum GlutenAnalyzer {

    // MARK: - Public API

    static func analyze(text: String, averageConfidence: Float) -> GlutenAnalysis {
        let matches = findMatches(in: text)

        let definite = matches.filter { $0.severity == .definite }
        let others = matches.filter { $0.severity != .definite }

        // 1. Any real gluten ingredient is decisive, whatever the photo quality.
        if !definite.isEmpty {
            return GlutenAnalysis(result: .containsGluten, matches: matches,
                                  reason: .found(encodeTerms(definite)))
        }

        // 2. Text too short / unclear => we can't promise anything.
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount < 8 || averageConfidence < 0.5 {
            return GlutenAnalysis(result: .uncertain, matches: matches, reason: .unclear)
        }

        // 3. Ambiguous / "may contain" wording / possibly misread words.
        if !others.isEmpty {
            return GlutenAnalysis(result: .uncertain, matches: matches,
                                  reason: .possible(encodeTerms(others)))
        }

        // 4. We never saw an ingredients list (maybe photographed the front of the pack).
        let hasHeader = text.range(of: "ingredient", options: .caseInsensitive) != nil
                     || ArabicNLP.hasIngredientsHeader(in: text)
        if !hasHeader {
            return GlutenAnalysis(result: .uncertain, matches: matches, reason: .noIngredientsList)
        }

        // 5. Ingredients list found, nothing suspicious.
        return GlutenAnalysis(result: .noGlutenDetected, matches: matches, reason: .clean)
    }

    // MARK: - Matching

    /// Compiled once, reused for every scan.
    private static let rules: [(term: String, severity: MatchSeverity, regex: NSRegularExpression)] = {
        let all = GlutenKeywords.definite.map { ($0, MatchSeverity.definite) }
                + GlutenKeywords.caution.map { ($0, MatchSeverity.caution) }
        return all.compactMap { term, severity in
            guard let regex = makeRegex(for: term) else { return nil }
            return (term, severity, regex)
        }
    }()

    private static let advisoryRegex: NSRegularExpression? = {
        let phrases = GlutenKeywords.advisoryPhrases
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
            .joined(separator: "|")
        // From the phrase up to the next period / semicolon (max 120 chars).
        return try? NSRegularExpression(pattern: "(?:\(phrases))[^.;]{0,120}", options: .caseInsensitive)
    }()

    private static func makeRegex(for term: String) -> NSRegularExpression? {
        var core = NSRegularExpression.escapedPattern(for: term)
        core = core.replacingOccurrences(of: " ", with: "[\\s-]+")        // "malt extract" / "malt-extract"
        core = core.replacingOccurrences(of: "'", with: "['’‘]?")        // OCR may return a curly apostrophe
        // \b stops "buckwheat" and "maltodextrin" from matching.
        // The lookahead skips "wheat-free" / "gluten free".
        let pattern = "\\b(?:\(core))(?:s|es)?\\b(?![\\s-]*free\\b)"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func findMatches(in text: String) -> [GlutenMatch] {
        let full = NSRange(text.startIndex..., in: text)
        let ns = text as NSString

        // Where are the "may contain..." clauses?
        let advisoryRanges = advisoryRegex?.matches(in: text, range: full).map(\.range) ?? []

        var found: [GlutenMatch] = []
        for rule in rules {
            for m in rule.regex.matches(in: text, range: full) {
                let inAdvisory = advisoryRanges.contains { NSIntersectionRange($0, m.range).length > 0 }
                // "may contain wheat" is a warning, not a confirmed ingredient.
                let severity: MatchSeverity = (inAdvisory && rule.severity == .definite) ? .advisory : rule.severity
                found.append(GlutenMatch(term: ns.substring(with: m.range),
                                         range: m.range,
                                         severity: severity))
            }
        }

        // English NLP layer: inflected forms and OCR-damaged words the exact rules missed.
        let extra = NLPEngine.extraMatches(in: text, skipping: found.map(\.range)).map { m -> GlutenMatch in
            let inAdvisory = advisoryRanges.contains { NSIntersectionRange($0, m.range).length > 0 }
            guard inAdvisory, m.severity == .definite else { return m }
            return GlutenMatch(term: m.term, range: m.range, severity: .advisory, suggestion: m.suggestion)
        }
        found.append(contentsOf: extra)

        // Arabic NLP layer (has its own normalisation, stemming and context rules).
        found.append(contentsOf: ArabicNLP.findMatches(in: text))

        return found.sorted { $0.range.location < $1.range.location }
    }

    /// "wheat; whaat→wheat" — unique terms, language-neutral (formatted when displayed).
    private static func encodeTerms(_ matches: [GlutenMatch]) -> String {
        var seen = Set<String>()
        return matches
            .map { m -> String in
                if let s = m.suggestion { return "\(m.term.lowercased())→\(s)" }
                return m.term.lowercased()
            }
            .filter { seen.insert($0).inserted }
            .joined(separator: "; ")
    }
}
