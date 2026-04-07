import SwiftUI
import os

struct CleanupSimulatorsView: View {
    let viewModel: CleanupSimulatorsViewModel

    var body: some View {
        let cleanupCandidates = viewModel.cleanupCandidates
        let candidateGroups = viewModel.cleanupCandidateGroups
        let isDeletingCandidates = !viewModel.deletingCandidateIDs.isEmpty

        Menu {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                Divider()
            }

            if viewModel.isLoadingCleanupCandidates {
                Text("Inspecting simulator installations…")
            } else if cleanupCandidates.isEmpty {
                Text("No invalid simulators found")
            }

            Divider()

            Menu("Why a simulator can be deleted") {
                Text("Cleanup candidates are detected from CoreSimulator metadata and simulator directories.")
                Divider()
                Text("Missing Runtime: the simulator references a runtime that is no longer installed.")
                Text("Missing Device Type: the simulator references a device type profile that is no longer available.")
                Text("Unavailable: CoreSimulator reports the simulator as unavailable.")
                Text("Orphaned Directory: a simulator directory exists on disk but is no longer registered with CoreSimulator.")
                Text("Missing Metadata: the simulator directory is missing its device.plist file.")
                Text("Unreadable Metadata: the simulator metadata exists but cannot be decoded.")
            }

            if !viewModel.isLoadingCleanupCandidates, !cleanupCandidates.isEmpty {
                Divider()

                Button(role: .destructive) {
                    viewModel.deleteAllCleanupCandidates()
                } label: {
                    Text(isDeletingCandidates ? "Cleaning Up All…" : "Cleanup All Simulators (\(cleanupCandidates.count))")
                }
                .disabled(isDeletingCandidates)

                Divider()

                ForEach(candidateGroups) { group in
                    Menu("\(group.title) (\(group.count))") {
                        Button(role: .destructive) {
                            viewModel.deleteAll(in: group)
                        } label: {
                            Text(viewModel.isDeleting(group) ? "Deleting \(group.title)…" : "Delete All in \(group.title) (\(group.count))")
                        }
                        .disabled(viewModel.isDeleting(group))

                        Divider()

                        ForEach(group.candidates) { candidate in
                            Menu(candidate.name) {
                                cleanupCandidateDetails(candidate, includesDeleteAction: true)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Refresh Cleanup Scan") {
                viewModel.refreshCleanupCandidates()
            }
            .disabled(viewModel.isLoadingCleanupCandidates || isDeletingCandidates)
        } label: {
            Label(viewModel.cleanupButtonText, systemImage: viewModel.cleanupButtonIcon)
        }
        .task {
            os_log("Cleanup menu task triggered")
            viewModel.loadCleanupCandidatesIfNeeded()
        }
    }

    @ViewBuilder
    private func cleanupCandidateDetails(
        _ candidate: SimulatorCleanupCandidate,
        includesDeleteAction: Bool
    ) -> some View {
        Text("Reason: \(candidate.reasonSummary)")

        if let detailMessage = candidate.detailMessage {
            Text(detailMessage)
        }

        if let platform = candidate.formattedPlatform {
            Text("Platform: \(platform)")
        }

        if let osVersion = candidate.osVersion {
            Text("OS: \(osVersion)")
        }

        if let formattedDiskUsage = candidate.formattedDiskUsage {
            Text("Disk Usage: \(formattedDiskUsage)")
        }

        if let lastBootedAt = candidate.lastBootedAt {
            Text("Last Booted: \(lastBootedAt.formatted(date: .abbreviated, time: .shortened))")
        }

        if let udid = candidate.udid {
            Text(udid)
                .textSelection(.enabled)
        }

        if includesDeleteAction {
            Divider()

            Button(role: .destructive) {
                viewModel.delete(candidate)
            } label: {
                Text(viewModel.isDeleting(candidate) ? "Deleting…" : "Delete Simulator")
            }
            .disabled(viewModel.isDeleting(candidate))
        }
    }
}
