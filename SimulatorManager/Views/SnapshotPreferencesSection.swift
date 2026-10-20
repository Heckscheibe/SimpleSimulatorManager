//
//  SnapshotPreferencesSection.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.26.
//

import SwiftUI

/// Where Save Snapshot to Folder writes, and what it captures.
struct SnapshotPreferencesSection: View {
    @ObservedObject var settings: Settings
    var destinationChooser: SnapshotDestinationChoosing = OpenPanelSnapshotDestinationChooser()

    var body: some View {
        Section("Snapshots") {
            LabeledContent("Save to") {
                Text(folderDescription)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(settings.snapshotExportFolder?.path ?? "")
            }

            HStack {
                Spacer()

                Button("Ask Every Time") {
                    settings.snapshotExportFolder = nil
                }
                .disabled(settings.snapshotExportFolder == nil)

                Button("Choose…") {
                    chooseFolder()
                }
            }

            Toggle("Include caches and temporary files", isOn: settings.binding(for: \.includeCachesInSnapshots))

            Text(Self.privacyNote)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private extension SnapshotPreferencesSection {
    /// Downloads is commonly synced, shared and uploaded from, which the internal store never was.
    static let privacyNote = "A snapshot is an unencrypted copy of everything the app stored, "
        + "including tokens and personal data. Take care where you save and share it."

    var folderDescription: String {
        guard let folder = settings.snapshotExportFolder else {
            return "Ask every time"
        }

        return (folder.path as NSString).abbreviatingWithTildeInPath
    }

    func chooseFolder() {
        Task {
            let choice = await destinationChooser.chooseFolder(message: nil,
                                                               startingAt: settings.snapshotExportFolder,
                                                               offersUseAsDefault: false)

            if let choice {
                settings.snapshotExportFolder = choice.url
            }
        }
    }
}
