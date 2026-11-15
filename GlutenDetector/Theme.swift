//
//  Theme.swift
//  GlutenDetector
//
//  Central place for colors + a reusable button style.
//  Keeping this in one file means changing the app's look later
//  only requires editing one place instead of every screen.
//

import SwiftUI

enum AppColor {
    static let primary = Color.blue
    static let danger = Color.red        // "Contains Gluten"
    static let safe = Color.green        // "No Gluten Detected"
    static let warning = Color.orange    // "Uncertain"
    static let background = Color(.systemGroupedBackground)
}

/// A simple full-width, rounded, filled button style used across
/// Home / Result / History so every button in the app looks the same.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = AppColor.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .cornerRadius(12)
    }
}

extension View {
    /// Convenience so you can just write `.primaryButton()`
    func primaryButton(color: Color = AppColor.primary) -> some View {
        self.buttonStyle(PrimaryButtonStyle(color: color))
    }
}
