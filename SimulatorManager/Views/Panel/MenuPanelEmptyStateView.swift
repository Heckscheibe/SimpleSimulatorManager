//
//  MenuPanelEmptyStateView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import SwiftUI

/// Shown when a query matches nothing.
///
/// A blank panel reads as a bug. This says what happened, and it occupies the same floor the result
/// list does, so deleting back into a matching query does not make the panel jump.
struct MenuPanelEmptyStateView: View {
    let query: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No matches")
                .font(MenuPanelStyle.titleFont)
                .foregroundStyle(.secondary)

            Text(query)
                .font(MenuPanelStyle.subtitleFont)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, MenuPanelStyle.rowHorizontalPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: MenuPanelStyle.searchResultsMinimumHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No matches for \(query)")
    }
}
