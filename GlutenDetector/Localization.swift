//
//  Localization.swift
//  GlutenDetector
//
//  English / Arabic switching inside the app (no system settings needed).
//  The current language lives in @AppStorage("appLanguage") and is pushed
//  to every screen through the SwiftUI environment from GlutenDetectorApp.
//

import SwiftUI

enum AppLanguage: String {
    case english = "en"
    case arabic = "ar"

    var isArabic: Bool { self == .arabic }
    var toggled: AppLanguage { isArabic ? .english : .arabic }
    var layoutDirection: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }
    var locale: Locale { Locale(identifier: rawValue) }

    /// Text on the switch button = the language you will switch TO.
    var switchButtonTitle: String { isArabic ? "English" : "العربية" }

    func t(_ key: L) -> String { key.text(self) }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

/// Every piece of UI text, with its English and Arabic version.
enum L: String {
    case appTitle, tagline, home
    case takePhoto, chooseLibrary, checkLabel, viewHistory
    case cameraUnavailableTitle, openSettings, cancel
    case noCameraMsg, cameraDeniedMsg, cameraOffMsg, cameraUnavailableMsg, missingKeyMsg
    case result, readingLabel, scanAgain, tryAgain, extractedText, disclaimer, noPhoto
    case history, noScansYet, noScansDesc, scan
    case containsGluten, noGlutenDetected, uncertain
    case arabicOCRUnavailable, maybe
    case ocrInvalidImage, ocrFailed

    func text(_ lang: AppLanguage) -> String {
        guard let pair = Self.table[self] else { return rawValue }
        return lang.isArabic ? pair.ar : pair.en
    }

    private static let table: [L: (en: String, ar: String)] = [
        .appTitle: ("Gluten Detector", "كاشف الغلوتين"),
        .tagline: ("Scan a food label to check for gluten.", "امسح ملصق الغذاء للتحقق من وجود الغلوتين."),
        .home: ("Home", "الرئيسية"),

        .takePhoto: ("Take Photo", "التقاط صورة"),
        .chooseLibrary: ("Choose from Library", "اختيار من المعرض"),
        .checkLabel: ("Check This Label", "افحص هذا الملصق"),
        .viewHistory: ("View Scan History", "عرض سجل الفحوصات"),

        .cameraUnavailableTitle: ("Camera Unavailable", "الكاميرا غير متاحة"),
        .openSettings: ("Open Settings", "فتح الإعدادات"),
        .cancel: ("Cancel", "إلغاء"),

        .noCameraMsg: (
            "No camera is available on this device (e.g. the Simulator). Please try \"Choose from Library\" instead, or run this on a real iPhone.",
            "لا توجد كاميرا متاحة على هذا الجهاز (مثل المحاكي). جرّب \"اختيار من المعرض\" أو شغّل التطبيق على iPhone حقيقي."),
        .cameraDeniedMsg: (
            "Camera access was denied. You can enable it in Settings, or use \"Choose from Library\" instead.",
            "تم رفض الوصول إلى الكاميرا. يمكنك تفعيله من الإعدادات أو استخدام \"اختيار من المعرض\"."),
        .cameraOffMsg: (
            "Camera access is turned off for this app. Enable it in Settings, or use \"Choose from Library\" instead.",
            "الوصول إلى الكاميرا متوقف لهذا التطبيق. فعّله من الإعدادات أو استخدم \"اختيار من المعرض\"."),
        .cameraUnavailableMsg: (
            "Camera access is unavailable right now. Please try \"Choose from Library\" instead.",
            "الكاميرا غير متاحة حالياً. جرّب \"اختيار من المعرض\"."),
        .missingKeyMsg: (
            "Missing Info.plist key: add \"Privacy - Camera Usage Description\" (NSCameraUsageDescription) in the target's Info tab.",
            "مفتاح Info.plist مفقود: أضف \"Privacy - Camera Usage Description\" (NSCameraUsageDescription) من تبويب Info في الـ Target."),

        .result: ("Result", "النتيجة"),
        .readingLabel: ("Reading label…", "جارٍ قراءة الملصق…"),
        .scanAgain: ("Scan Again", "فحص جديد"),
        .tryAgain: ("Try Again", "إعادة المحاولة"),
        .extractedText: ("Extracted Text", "النص المستخرج"),
        .disclaimer: ("This app is a decision-support tool, not medical advice.",
                      "هذا التطبيق أداة مساعدة على اتخاذ القرار وليس نصيحة طبية."),
        .noPhoto: ("No photo to analyse.", "لا توجد صورة للتحليل."),

        .history: ("History", "السجل"),
        .noScansYet: ("No Scans Yet", "لا توجد فحوصات بعد"),
        .noScansDesc: ("Your past label scans will appear here.", "ستظهر هنا فحوصاتك السابقة."),
        .scan: ("Scan", "فحص"),

        .containsGluten: ("Contains Gluten", "يحتوي على غلوتين"),
        .noGlutenDetected: ("No Gluten Detected", "لم يُكتشف غلوتين"),
        .uncertain: ("Uncertain", "غير مؤكد"),

        .arabicOCRUnavailable: (
            "This iPhone's iOS version can't read Arabic text yet, so only English was read. Update iOS to read Arabic labels.",
            "إصدار iOS في هذا الجهاز لا يدعم قراءة النص العربي، لذلك قُرئت الإنجليزية فقط. حدّث النظام لقراءة الملصقات العربية."),
        .maybe: ("maybe", "ربما"),

        .ocrInvalidImage: ("The photo could not be read. Please try another one.",
                           "تعذّرت قراءة الصورة. جرّب صورة أخرى."),
        .ocrFailed: ("Text recognition failed:", "فشلت قراءة النص:")
    ]
}
