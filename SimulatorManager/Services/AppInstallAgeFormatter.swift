//
//  AppInstallAgeFormatter.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 28.10.26.
//

import Foundation
import SimulatorCore

/// Turns an app's bundle date into the age the panel shows.
///
/// Holds its formatters because constructing a `RelativeDateTimeFormatter` is not free and the tree
/// is rebuilt on every render, once per app row. `now` is a parameter rather than read here so the
/// result is a function of its inputs, the way the rest of the tree is, and so a test can say what
/// time it is.
@MainActor
final class AppInstallAgeFormatter {
    private let relativeFormatter: RelativeDateTimeFormatter
    private let absoluteFormatter: DateFormatter

    /// Younger than this reads as "just now" rather than as "0 sec ago" or, for a date a hair in the
    /// future after clock skew, "in 1 sec".
    private static let justNowThreshold: TimeInterval = 60

    /// Defaults follow the system rather than what they were at launch: a menu bar app runs for weeks,
    /// and a changed region, language or time zone should reach the next date it writes.
    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        relativeFormatter.locale = locale

        absoluteFormatter = DateFormatter()
        absoluteFormatter.dateStyle = .medium
        absoluteFormatter.timeStyle = .short
        absoluteFormatter.locale = locale
        absoluteFormatter.timeZone = timeZone
    }

    private static let dayCountFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = .day
        formatter.unitsStyle = .full

        return formatter
    }()

    /// "1 day", "7 days": pluralised and localised by the system, and the one place the threshold is
    /// spelled out so the submenu and Preferences cannot disagree.
    static func dayCount(_ days: Int) -> String {
        dayCountFormatter.string(from: DateComponents(day: days)) ?? "\(days)"
    }

    static func dayCount(of interval: TimeInterval) -> String {
        dayCount(Int((interval / (24 * 60 * 60)).rounded()))
    }

    /// `nil` when the app has no bundle date: a missing date shows nothing rather than an epoch or a
    /// guess, because a fabricated age is worse than none for a feature whose point is trust.
    func age(
        for app: any SimulatorApp,
        changeType: ChangeType?,
        now: Date,
        staleAfter: TimeInterval
    ) -> AppInstallAge? {
        guard let bundleDate = app.bundleModifiedAt else {
            return nil
        }

        let elapsed = max(0, now.timeIntervalSince(bundleDate))

        return AppInstallAge(kind: Self.kind(for: changeType),
                             relative: relativeText(for: bundleDate, elapsed: elapsed, now: now),
                             absolute: absolute(bundleDate),
                             isStale: elapsed >= staleAfter,
                             staleThreshold: staleAfter)
    }

    func absolute(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }

    private func relativeText(for date: Date, elapsed: TimeInterval, now: Date) -> String {
        guard elapsed >= Self.justNowThreshold else {
            return String(localized: "just now")
        }

        // Clamped to `now` so a bundle dated slightly ahead of this machine's clock cannot read "in 2 min".
        return relativeFormatter.localizedString(for: min(date, now), relativeTo: now)
    }

    private static func kind(for changeType: ChangeType?) -> AppInstallAge.Kind? {
        switch changeType {
        case .installed: .installed
        case .updated: .updated
        case .removed, nil: nil
        }
    }
}
