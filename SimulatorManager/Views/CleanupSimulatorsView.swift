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
            } else {
                Button(role: .destructive) {
                    viewModel.deleteAllCleanupCandidates()
                } label: {
                    Text(isDeletingCandidates ? "Cleaning Up All…" : "Delete All Simulators (\(cleanupCandidates.count))")
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
}
