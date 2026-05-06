// DidIFeedTheDogWidget/WidgetColors.swift
import SwiftUI
import UIKit

// Adaptive widget colors. The dark-mode background preserves the original
// custom shade (slightly raised from pure black) so the widget keeps its
// "card" feel; light mode falls through to systemBackground (white) so the
// widget blends with light home screens instead of being a black island.
enum WidgetColors {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : UIColor.systemBackground
    })

    // Used for the thin row separators between pet rows. white.opacity(0.06)
    // would vanish in light mode; primary (auto-adapts) at low opacity gives
    // a faint divider in both modes.
    static let divider = Color.primary.opacity(0.08)
}
