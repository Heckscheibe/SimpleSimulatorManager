import SwiftUI
import os

struct CleanupSimulatorsView: View {
    let viewModel: CleanupSimulatorsViewModel

    var body: some View {
        let cleanupCandidates = viewModel.cleanupCandidates

        Menu {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                Divider()
            }

            if viewModel.isLoadingCleanupCandidates {
                Text("Inspecting simulator installations…")
            } else if cleanupCandidates.isEmpty {
                Text("No invalid simulators found")
            } else {
                ForEach(Array(cleanupCandidates.enumerated()), id: \.element.id) { _, candidate in
                    Menu(candidate.name) {
                        Text(candidate.reasonSummary)

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

            Divider()

            Button("Refresh Cleanup Scan") {
                viewModel.refreshCleanupCandidates()
            }
            .disabled(viewModel.isLoadingCleanupCandidates)
        } label: {
            Label(viewModel.cleanupButtonText, systemImage: viewModel.cleanupButtonIcon)
        }
        .task {
            os_log("Cleanup menu task triggered")
            viewModel.loadCleanupCandidatesIfNeeded()
        }
    }
}
