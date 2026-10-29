import SwiftUI
import SimulatorCore

/// The runtime cleanup submenu for the native `NSMenu`, kept in step with the panel's version
/// built by `MenuTreeBuilder+CleanupRuntimes`.
struct CleanupRuntimesView: View {
    let viewModel: CleanupRuntimesViewModel

    var body: some View {
        let isDeleting = !viewModel.deletingCandidateIDs.isEmpty

        Menu {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                Divider()
            }

            if viewModel.isLoading {
                Text("Inspecting simulator runtimes…")
            } else if viewModel.candidates.isEmpty {
                Text(viewModel.emptyStateText)
            }

            Divider()

            Menu("Why a runtime can be removed") {
                Text("Unusable: CoreSimulator marks the runtime image as unusable.")
                Text("Superseded: a newer build of the same runtime is installed.")
                Text("Unused: not used for \(SimulatorRuntimeCleanupService.defaultUnusedThresholdDays) days or more.")
                Text("Removing a runtime cannot be undone; it has to be downloaded again.")
            }

            if !viewModel.isLoading, !viewModel.candidates.isEmpty {
                Divider()

                Button(role: .destructive) {
                    viewModel.deleteAll()
                } label: {
                    Text(isDeleting ? "Removing All…" : "Remove All Runtimes (\(viewModel.candidates.count))")
                }
                .disabled(isDeleting)

                Divider()

                ForEach(viewModel.candidateGroups) { group in
                    Menu("\(group.title) (\(group.count))") {
                        Button(role: .destructive) {
                            viewModel.deleteAll(in: group)
                        } label: {
                            Text(viewModel.isDeleting(group) ? "Removing \(group.title)…" : "Remove All in \(group.title) (\(group.count))")
                        }
                        .disabled(viewModel.isDeleting(group))

                        Divider()

                        ForEach(group.candidates) { candidate in
                            Menu(candidate.name) {
                                details(candidate)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Refresh Runtime Scan") {
                viewModel.refresh()
            }
            .disabled(viewModel.isLoading || isDeleting)
        } label: {
            Label(viewModel.buttonText, systemImage: viewModel.buttonIcon)
        }
        .task {
            viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func details(_ candidate: SimulatorRuntimeCleanupCandidate) -> some View {
        Text("Reason: \(candidate.reasonSummary)")

        if let detailMessage = candidate.detailMessage, !detailMessage.isEmpty {
            Text(detailMessage)
        }

        if let size = candidate.formattedSize {
            Text("Size: \(size)")
        }

        if let lastUsedAt = candidate.lastUsedAt {
            Text("Last Used: \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))")
        }

        if candidate.affectedSimulatorCount > 0 {
            Text("\(candidate.affectedSimulatorCount) simulators will become unavailable")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.delete(candidate)
        } label: {
            Text(viewModel.isDeleting(candidate) ? "Removing…" : "Remove Runtime")
        }
        .disabled(viewModel.isDeleting(candidate))
    }
}
