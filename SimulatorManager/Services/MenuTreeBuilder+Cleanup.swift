//
//  MenuTreeBuilder+Cleanup.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

/// The cleanup section, kept apart from the rest of the tree because it is by far the deepest part
/// of the menu: candidates are grouped by OS version, each group can be deleted wholesale, and each
/// candidate drills down again into why it qualified and what deleting it would remove.
extension MenuTreeBuilder {
    func cleanupNode() -> MenuNode {
        .submenu(id: "cleanup",
                 title: cleanupViewModel.cleanupButtonText,
                 iconName: cleanupViewModel.cleanupButtonIcon,
                 onEnter: { cleanupViewModel.loadCleanupCandidatesIfNeeded() },
                 children: cleanupChildNodes())
    }

    func cleanupChildNodes() -> [MenuNode] {
        var nodes: [MenuNode] = []

        if let errorMessage = cleanupViewModel.errorMessage {
            nodes.append(.informational(id: "cleanup.error", title: errorMessage))
            nodes.append(.divider(id: "cleanup.error.divider"))
        }

        if cleanupViewModel.isLoadingCleanupCandidates {
            nodes.append(.informational(id: "cleanup.loading", title: "Inspecting simulator installations…"))
        } else if cleanupViewModel.cleanupCandidates.isEmpty {
            nodes.append(.informational(id: "cleanup.empty", title: "No invalid simulators found"))
        }

        nodes.append(contentsOf: cleanupCandidateNodes())
        nodes.append(.divider(id: "cleanup.divider.beforeRefresh"))
        nodes.append(cleanupRefreshNode())
        // Last, because it is reference material rather than something to act on, and it is long
        // enough to bury the refresh action if it came first.
        nodes.append(.divider(id: "cleanup.divider.beforeExplanation"))
        nodes.append(contentsOf: cleanupExplanationNodes())

        return nodes
    }
}

// MARK: - Candidates

private extension MenuTreeBuilder {
    var isDeletingCandidates: Bool {
        !cleanupViewModel.deletingCandidateIDs.isEmpty
    }

    func cleanupCandidateNodes() -> [MenuNode] {
        guard !cleanupViewModel.isLoadingCleanupCandidates, !cleanupViewModel.cleanupCandidates.isEmpty else {
            return []
        }

        return [
            .divider(id: "cleanup.divider.beforeDeleteAll"),
            cleanupDeleteAllNode(),
            .divider(id: "cleanup.divider.afterDeleteAll")
        ] + cleanupViewModel.cleanupCandidateGroups.map { cleanupGroupNode(for: $0) }
    }

    func cleanupDeleteAllNode() -> MenuNode {
        let count = cleanupViewModel.cleanupCandidates.count
        let title = isDeletingCandidates ? "Cleaning Up All…" : "Cleanup All Simulators (\(count))"

        return .action(id: "cleanup.deleteAll",
                       title: title,
                       isEnabled: !isDeletingCandidates,
                       isDestructive: true,
                       actions: [MenuActionItem(title: title) { cleanupViewModel.deleteAllCleanupCandidates() }])
    }

    func cleanupGroupNode(for group: CleanupSimulatorsViewModel.CandidateGroup) -> MenuNode {
        let isDeleting = cleanupViewModel.isDeleting(group)
        let deleteTitle = isDeleting
            ? "Deleting \(group.title)…"
            : "Delete All in \(group.title) (\(group.count))"
        let deleteAction = MenuActionItem(title: deleteTitle) { cleanupViewModel.deleteAll(in: group) }
        let deleteNode = MenuNode.action(id: "cleanup.group.\(group.id).deleteAll",
                                         title: deleteTitle,
                                         isEnabled: !isDeleting,
                                         isDestructive: true,
                                         actions: [deleteAction])
        let children = [deleteNode, .divider(id: "cleanup.group.\(group.id).divider")]
            + group.candidates.map { cleanupCandidateNode(for: $0) }

        return .submenu(id: "cleanup.group.\(group.id)",
                        title: "\(group.title) (\(group.count))",
                        children: children)
    }

    func cleanupCandidateNode(for candidate: SimulatorCleanupCandidate) -> MenuNode {
        let prefix = "cleanup.candidate.\(candidate.id)"
        let isDeleting = cleanupViewModel.isDeleting(candidate)
        let deleteTitle = isDeleting ? "Deleting…" : "Delete Simulator"
        let deleteAction = MenuActionItem(title: deleteTitle) { cleanupViewModel.delete(candidate) }
        let deleteNode = MenuNode.action(id: "\(prefix).delete",
                                         title: deleteTitle,
                                         isEnabled: !isDeleting,
                                         isDestructive: true,
                                         actions: [deleteAction])
        let children = cleanupCandidateDetailNodes(for: candidate, prefix: prefix)
            + [.divider(id: "\(prefix).divider"), deleteNode]

        return .submenu(id: prefix, title: candidate.name, children: children)
    }

    func cleanupCandidateDetailNodes(for candidate: SimulatorCleanupCandidate, prefix: String) -> [MenuNode] {
        var nodes: [MenuNode] = [
            .informational(id: "\(prefix).reason", title: "Reason: \(candidate.reasonSummary)")
        ]

        if let detailMessage = candidate.detailMessage {
            nodes.append(.informational(id: "\(prefix).detail", title: detailMessage))
        }

        if let platform = candidate.formattedPlatform {
            nodes.append(.informational(id: "\(prefix).platform", title: "Platform: \(platform)"))
        }

        if let osVersion = candidate.osVersion {
            nodes.append(.informational(id: "\(prefix).osVersion", title: "OS: \(osVersion)"))
        }

        if let formattedDiskUsage = candidate.formattedDiskUsage {
            nodes.append(.informational(id: "\(prefix).diskUsage", title: "Disk Usage: \(formattedDiskUsage)"))
        }

        if let lastBootedAt = candidate.lastBootedAt {
            let formatted = lastBootedAt.formatted(date: .abbreviated, time: .shortened)
            nodes.append(.informational(id: "\(prefix).lastBooted", title: "Last Booted: \(formatted)"))
        }

        if let udid = candidate.udid {
            nodes.append(.informational(id: "\(prefix).udid", title: udid))
        }

        return nodes
    }
}

// MARK: - Static content

private extension MenuTreeBuilder {
    func cleanupRefreshNode() -> MenuNode {
        let isEnabled = !cleanupViewModel.isLoadingCleanupCandidates && !isDeletingCandidates
        let refresh = MenuActionItem(title: "Refresh Cleanup Scan") { cleanupViewModel.refreshCleanupCandidates() }

        return .action(id: "cleanup.refresh",
                       title: "Refresh Cleanup Scan",
                       isEnabled: isEnabled,
                       actions: [refresh])
    }

    /// Why a simulator qualifies for deletion, shown in the cleanup menu itself.
    ///
    /// This used to be a submenu, for one reason: `NSMenu` had no way to put a paragraph in front of
    /// the user, so an explanation had to be disguised as something to click. The panel draws rows
    /// that are only information, so the explanation can simply be there — which is what it always
    /// wanted to be, given that deleting a simulator cannot be undone.
    func cleanupExplanationNodes() -> [MenuNode] {
        let intro = "Cleanup candidates are detected from CoreSimulator metadata and simulator directories."
        let reasons = [
            ("missingRuntime", "Missing Runtime: the simulator references a runtime that is no longer installed."),
            ("missingDeviceType", "Missing Device Type: the simulator references a device type profile that is no longer available."),
            ("unavailable", "Unavailable: CoreSimulator reports the simulator as unavailable."),
            ("orphanedDirectory", "Orphaned Directory: a simulator directory exists on disk but is no longer registered with CoreSimulator."),
            ("missingMetadata", "Missing Metadata: the simulator directory is missing its device.plist file."),
            ("unreadableMetadata", "Unreadable Metadata: the simulator metadata exists but cannot be decoded.")
        ]

        // Headed and marked, because a block of prose sitting under a list of deletions could
        // otherwise read as a report of what is about to happen rather than as background to it.
        let header = MenuNode.sectionHeader(id: "cleanup.explanation.header",
                                            title: "Information",
                                            iconName: "info.circle")

        return [header, .informational(id: "cleanup.explanation.intro", title: intro)] + reasons.map { key, text in
            .informational(id: "cleanup.explanation.\(key)", title: text)
        }
    }
}
