//
//  MenuSearchIndex.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

// MARK: - Index entry

/// One searchable thing: a simulator, or an app installed on a simulator.
///
/// Every string is normalised and tokenised when the entry is built, so matching a query is a
/// comparison and nothing more.
struct MenuSearchIndexEntry {
    let result: MenuSearchResult
    /// The fields a user is most likely to be typing: an app's display name, a device's name.
    let primaryFields: [MenuSearchField]
    /// Fields that disambiguate rather than identify: bundle identifier, OS version, and the
    /// device's name and OS version joined into one string.
    let secondaryFields: [MenuSearchField]
    /// Position in the recent-apps list, most recent first, or `Int.max` when this is not a recent
    /// app — so ordering by this key alone puts every recent app ahead of everything else.
    let recentRank: Int
    /// Devices sort ahead of apps at equal match quality.
    let kindRank: Int
    /// Normalised title, for the alphabetical tiebreak.
    let sortTitle: String
    /// Final, unique tiebreak, so the ordering is total.
    let sortIdentifier: String

    init(
        result: MenuSearchResult,
        primaryFields: [MenuSearchField],
        secondaryFields: [MenuSearchField],
        recentRank: Int?,
        kindRank: Int,
        sortTitle: String,
        sortIdentifier: String
    ) {
        self.result = result
        self.primaryFields = primaryFields
        self.secondaryFields = secondaryFields
        self.recentRank = recentRank ?? Int.max
        self.kindRank = kindRank
        self.sortTitle = sortTitle
        self.sortIdentifier = sortIdentifier
    }

    /// The best score any field achieves for `needle`, or `nil` when nothing matches.
    /// `needle` must already be normalised.
    func score(for needle: String) -> MenuSearchScore? {
        let scores = [
            Self.bestScore(for: needle, in: primaryFields, fieldTier: 0),
            Self.bestScore(for: needle, in: secondaryFields, fieldTier: 1)
        ]

        return scores.compactMap { $0 }.min()
    }

    private static func bestScore(
        for needle: String,
        in fields: [MenuSearchField],
        fieldTier: Int
    ) -> MenuSearchScore? {
        let bestQuality = fields.compactMap { $0.match(needle) }.min()

        return bestQuality.map { MenuSearchScore(quality: $0, fieldTier: fieldTier) }
    }
}

// MARK: - Field

/// A single searchable string, prepared once so that matching costs nothing per keystroke.
struct MenuSearchField {
    let value: String
    let tokens: [String]

    init(_ rawValue: String) {
        let normalizedValue = MenuSearchText.normalized(rawValue)

        value = normalizedValue
        tokens = MenuSearchText.tokens(in: normalizedValue)
    }

    /// - Parameter needle: An already normalised, non-empty query.
    func match(_ needle: String) -> MenuSearchMatchQuality? {
        guard value.contains(needle) else {
            return nil
        }

        if value.hasPrefix(needle) {
            return .prefix
        }

        return tokens.contains { $0.hasPrefix(needle) } ? .wordBoundary : .substring
    }
}

// MARK: - Scoring

/// How well a query matched a field, best first.
enum MenuSearchMatchQuality: Int, Comparable {
    case prefix
    case wordBoundary
    case substring

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How well a query matched an entry: the quality of the match, and whether it landed on a field
/// that identifies the thing or one that merely disambiguates it.
struct MenuSearchScore: Comparable {
    let quality: MenuSearchMatchQuality
    /// `0` for a primary field, `1` for a secondary one, so an equally good match on a name
    /// outranks one on a bundle identifier or an OS version.
    let fieldTier: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.quality != rhs.quality {
            return lhs.quality < rhs.quality
        }

        return lhs.fieldTier < rhs.fieldTier
    }
}

// MARK: - Text preparation

enum MenuSearchText {
    /// Case- and diacritic-insensitive, so `cafe` finds `Café` and `SAFARI` finds `Safari`.
    static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Splits on whitespace and `.`, so a query can match the start of any word: `pro` finds
    /// `iPhone 16 Pro`, and `pay` finds `com.example.payments`.
    static func tokens(in normalizedString: String) -> [String] {
        normalizedString
            .split(whereSeparator: { $0.isWhitespace || $0 == "." })
            .map(String.init)
    }
}
