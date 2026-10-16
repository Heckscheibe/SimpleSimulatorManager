//
//  MenuPanelStyle.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import SwiftUI

/// Metrics for the panel, chosen to read as a system menu rather than as a floating window.
///
/// `NSMenu` supplied all of this for free. None of it is guessed at random: the row height, insets
/// and corner radius match what AppKit draws for a standard menu item at the default control size.
enum MenuPanelStyle {
    static let width: CGFloat = 300
    /// The list scrolls inside the panel rather than growing past the screen. A machine with
    /// several Xcode versions can easily have dozens of simulators.
    static let maximumListHeight: CGFloat = 460

    static let rowMinimumHeight: CGFloat = 22
    static let rowHorizontalPadding: CGFloat = 9
    static let rowVerticalPadding: CGFloat = 3
    static let rowCornerRadius: CGFloat = 5

    /// Inset of the highlight and of the separators from the panel's edges.
    static let horizontalInset: CGFloat = 5
    static let listVerticalPadding: CGFloat = 5
    static let dividerVerticalPadding: CGFloat = 5

    static let iconWidth: CGFloat = 16
    static let titleFont: Font = .system(size: 13)
    static let subtitleFont: Font = .system(size: 11)
    static let disabledOpacity: Double = 0.4
}
