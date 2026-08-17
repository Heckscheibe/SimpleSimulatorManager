import AppKit
import Foundation

/// Asks the user to confirm a deletion that cannot be undone.
///
/// Cleanup has two deletion methods with very different consequences: orphaned directories are
/// moved to the Trash and stay recoverable, while devices registered with CoreSimulator go through
/// `simctl delete` and are gone for good. Only the latter needs a confirmation step, and it is
/// behind a protocol so the view model can be tested without showing UI.
@MainActor
protocol DestructiveActionConfirming: AnyObject {
    /// - Returns: `true` when the user confirmed deleting `simulatorCount` unrecoverable simulators.
    func confirmPermanentSimulatorDeletion(simulatorCount: Int) -> Bool
}

@MainActor
final class AlertDestructiveActionConfirmer: DestructiveActionConfirming {
    func confirmPermanentSimulatorDeletion(simulatorCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = simulatorCount == 1
            ? "Permanently delete this simulator?"
            : "Permanently delete \(simulatorCount) simulators?"
        alert.informativeText = """
        Simulators registered with CoreSimulator are removed with simctl. They cannot be restored \
        from the Trash, and any data they still contain is lost.
        """
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        // The menu closes as soon as the item is clicked, so bring the app forward to make sure
        // the alert is not stranded behind whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)

        return alert.runModal() == .alertFirstButtonReturn
    }
}
