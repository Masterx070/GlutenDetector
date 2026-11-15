//
//  GlutenKeywords.swift
//  GlutenDetector
//
//  FR7 / NFR6: the keyword lists live in their own file so you can add or
//  remove terms WITHOUT touching the analysis logic.
//  (Later you can move these arrays into a JSON file or SQLite.)
//

import Foundation

enum GlutenKeywords {

    // MARK: - English

    /// Ingredients that contain gluten. A match => "Contains Gluten".
    static let definite: [String] = [
        "gluten", "wheat", "barley", "rye", "malt", "spelt", "semolina",
        "durum", "farina", "farro", "kamut", "triticale", "einkorn", "emmer",
        "bulgur", "couscous", "seitan", "graham",
        "brewer's yeast", "brewers yeast",
        "triticum", "hordeum", "secale",              // Latin names used on some labels
        "enriched flour", "all-purpose flour", "bread flour", "white flour"
    ]

    /// Ingredients that MAY contain gluten (cross-contamination, ambiguous).
    /// A match (with no definite match) => "Uncertain".
    static let caution: [String] = [
        "oat", "beer", "soy sauce"      // plurals ("oats") are matched automatically
    ]

    /// Phrases that turn a nearby ingredient into a "may contain traces" warning.
    static let advisoryPhrases: [String] = [
        "may contain", "traces of", "produced in", "manufactured in",
        "processed in", "made in a facility", "shared facility", "shared equipment"
    ]

    /// Single words only (Vision's customWords can't take phrases).
    static var singleWords: [String] {
        (definite + caution).filter { !$0.contains(" ") && !$0.contains("-") && !$0.contains("'") }
    }

    // MARK: - Arabic (written naturally; ArabicNLP normalises them itself)

    static let arabicDefinite: [String] = [
        "قمح", "شعير", "جاودار", "سميد", "برغل", "كسكس",
        "غلوتين", "جلوتين", "غلوتن", "جلوتن",
        "مالت", "ملت", "مولت",
        "سيتان", "حنطة", "فريكة", "سبلت", "كاموت", "تريتيكالي", "فارو"
    ]

    static let arabicCaution: [String] = [
        "شوفان", "دقيق", "طحين", "بيرة", "صلصة صويا"
    ]

    /// "may contain / traces / shared facility" in Arabic.
    static let arabicAdvisoryPhrases: [String] = [
        "قد يحتوي", "قد تحتوي", "آثار", "تصنيعه في", "تصنيعها في",
        "ينتج في", "تنتج في", "منشأة", "مشتركة", "مشترك"
    ]

    /// "دقيق الأرز" (rice flour) etc. is not wheat, so flour followed by these is ignored.
    static let arabicSafeFlourQualifiers: [String] = [
        "أرز", "ذرة", "بطاطس", "بطاطا", "حمص", "لوز", "كينوا",
        "تابيوكا", "كسافا", "عدس", "فول", "كستناء", "جوز"
    ]

    /// "بدون غلوتين" / "خالٍ من القمح" / "لا يحتوي على غلوتين" => not a gluten ingredient.
    static let arabicNegationSingle: [String] = ["بدون", "خلو"]
    static let arabicNegationFree: [String] = ["خالي", "خال", "خالية"]

    /// Words that mark an ingredients list in Arabic.
    static let arabicIngredientHeaders: [String] = ["مكونات", "محتويات", "تركيبة", "مكون"]
}
