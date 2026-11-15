//
//  GlutenDetectorApp.swift
//  GlutenDetector
//
//  App entry point. Holds the chosen language (English / Arabic) and
//  pushes it to every screen, including right-to-left layout for Arabic.
//

import SwiftUI
import SwiftData

@main
struct GlutenDetectorApp: App {
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue

    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(\.appLanguage, lang)
                .environment(\.layoutDirection, lang.layoutDirection)
                .environment(\.locale, lang.locale)
        }
        // Creates the on-device database for saved scans.
        .modelContainer(for: ScanRecord.self)
    }
}
