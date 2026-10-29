import Foundation
import SimulatorCore

/// The runtime cleanup section. Shaped like the simulator cleanup one next to it, but smaller: a
/// runtime is a single multi-gigabyte download, so there is a per-platform group, a per-runtime
/// detail menu, and every deletion is permanent.
extension MenuTreeBuilder {
    func cleanupRuntimesNode() -> MenuNode {
        .submenu(id: "cleanupRuntimes",
                 title: cleanupRuntimesViewModel.buttonText,
                 iconName: cleanupRuntimesViewModel.buttonIcon,
                 onEnter: { cleanupRuntimesViewModel.loadIfNeeded() },
                 children: cleanupRuntimesChildNodes())
    }

    func cleanupRuntimesChildNodes() -> [MenuNode] {
        let viewModel = cleanupRuntimesViewModel
        var nodes: [MenuNode] = []

        if let errorMessage = viewModel.errorMessage {
            nodes.append(.informational(id: "cleanupRuntimes.error", title: errorMessage))
            nodes.append(.divider(id: "cleanupRuntimes.error.divider"))
        }

        if viewModel.isLoading {
            nodes.append(.informational(id: "cleanupRuntimes.loading", title: "Inspecting simulator runtimes…"))
        } else if viewModel.candidates.isEmpty {
            nodes.append(.informational(id: "cleanupRuntimes.empty", title: viewModel.emptyStateText))
        }

        nodes.append(contentsOf: cleanupRuntimeCandidateNodes())
        nodes.append(.divider(id: "cleanupRuntimes.divider.beforeRefresh"))
        nodes.append(cleanupRuntimesRefreshNode())
        nodes.append(.divider(id: "cleanupRuntimes.divider.beforeExplanation"))
        nodes.append(contentsOf: cleanupRuntimesExplanationNodes())

        return nodes
    }
}

private extension MenuTreeBuilder {
    var isDeletingRuntimes: Bool {
        !cleanupRuntimesViewModel.deletingCandidateIDs.isEmpty
    }

    func cleanupRuntimeCandidateNodes() -> [MenuNode] {
        let viewModel = cleanupRuntimesViewModel

        guard !viewModel.isLoading, !viewModel.candidates.isEmpty else {
            return []
        }

        let size = ByteCountFormatter.string(fromByteCount: viewModel.totalReclaimableBytes, countStyle: .file)
        let title = isDeletingRuntimes ? "Removing All…" : "Remove All Runtimes (\(viewModel.candidates.count), \(size))"
        let deleteAll = MenuNode.action(id: "cleanupRuntimes.deleteAll",
                                        title: title,
                                        isEnabled: !isDeletingRuntimes,
                                        isDestructive: true,
                                        actions: [MenuActionItem(title: title) { viewModel.deleteAll() }])

        return [
            .divider(id: "cleanupRuntimes.divider.beforeDeleteAll"),
            deleteAll,
            .divider(id: "cleanupRuntimes.divider.afterDeleteAll")
        ]
            + viewModel.candidateGroups.map { cleanupRuntimeGroupNode(for: $0) }
    }

    func cleanupRuntimeGroupNode(for group: CleanupRuntimesViewModel.CandidateGroup) -> MenuNode {
        let viewModel = cleanupRuntimesViewModel
        let isDeleting = viewModel.isDeleting(group)
        let title = isDeleting ? "Removing \(group.title)…" : "Remove All in \(group.title) (\(group.count))"
        let deleteNode = MenuNode.action(id: "cleanupRuntimes.group.\(group.id).deleteAll",
                                         title: title,
                                         isEnabled: !isDeleting,
                                         isDestructive: true,
                                         actions: [MenuActionItem(title: title) { viewModel.deleteAll(in: group) }])
        let children = [deleteNode, .divider(id: "cleanupRuntimes.group.\(group.id).divider")]
            + group.candidates.map { cleanupRuntimeCandidateNode(for: $0) }

        return .submenu(id: "cleanupRuntimes.group.\(group.id)",
                        title: "\(group.title) (\(group.count))",
                        children: children)
    }

    func cleanupRuntimeCandidateNode(for candidate: SimulatorRuntimeCleanupCandidate) -> MenuNode {
        let viewModel = cleanupRuntimesViewModel
        let prefix = "cleanupRuntimes.candidate.\(candidate.id)"
        let isDeleting = viewModel.isDeleting(candidate)
        let deleteTitle = isDeleting ? "Removing…" : "Remove Runtime"
        let deleteNode = MenuNode.action(id: "\(prefix).delete",
                                         title: deleteTitle,
                                         isEnabled: !isDeleting,
                                         isDestructive: true,
                                         actions: [MenuActionItem(title: deleteTitle) { viewModel.delete(candidate) }])
        let children = cleanupRuntimeDetailNodes(for: candidate, prefix: prefix)
            + [.divider(id: "\(prefix).divider"), deleteNode]

        return .submenu(id: prefix, title: candidate.name, children: children)
    }

    func cleanupRuntimeDetailNodes(for candidate: SimulatorRuntimeCleanupCandidate, prefix: String) -> [MenuNode] {
        var nodes: [MenuNode] = [
            .informational(id: "\(prefix).reason", title: "Reason: \(candidate.reasonSummary)")
        ]

        if let detailMessage = candidate.detailMessage, !detailMessage.isEmpty {
            nodes.append(.informational(id: "\(prefix).detail", title: detailMessage))
        }

        if let size = candidate.formattedSize {
            nodes.append(.informational(id: "\(prefix).size", title: "Size: \(size)"))
        }

        if let lastUsedAt = candidate.lastUsedAt {
            let formatted = lastUsedAt.formatted(date: .abbreviated, time: .shortened)
            nodes.append(.informational(id: "\(prefix).lastUsed", title: "Last Used: \(formatted)"))
        }

        if candidate.affectedSimulatorCount > 0 {
            let noun = candidate.affectedSimulatorCount == 1 ? "simulator" : "simulators"
            nodes.append(.informational(id: "\(prefix).affected",
                                        title: "\(candidate.affectedSimulatorCount) \(noun) will become unavailable"))
        }

        if candidate.bootedSimulatorCount > 0 {
            nodes.append(.informational(id: "\(prefix).booted",
                                        title: "\(candidate.bootedSimulatorCount) running will be shut down"))
        }

        return nodes
    }

    func cleanupRuntimesRefreshNode() -> MenuNode {
        let isEnabled = !cleanupRuntimesViewModel.isLoading && !isDeletingRuntimes
        let refresh = MenuActionItem(title: "Refresh Runtime Scan") { cleanupRuntimesViewModel.refresh() }

        return .action(id: "cleanupRuntimes.refresh",
                       title: "Refresh Runtime Scan",
                       isEnabled: isEnabled,
                       actions: [refresh])
    }

    func cleanupRuntimesExplanationNodes() -> [MenuNode] {
        let reasons = [
            ("unusable", "Unusable: CoreSimulator marks the runtime image as unusable."),
            ("superseded", "Superseded: a newer build of the same runtime is installed."),
            ("unused", "Unused: not used for \(SimulatorRuntimeCleanupService.defaultUnusedThresholdDays) days or more."),
            ("permanent", "Removing a runtime cannot be undone; it has to be downloaded again.")
        ]
        let header = MenuNode.sectionHeader(id: "cleanupRuntimes.explanation.header",
                                            title: "Information",
                                            iconName: "info.circle")

        return [header] + reasons.map { key, text in
            .informational(id: "cleanupRuntimes.explanation.\(key)", title: text)
        }
    }
}
