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

    /// - Returns: `true` when the user confirmed deleting `runtimeCount` simulator runtimes.
    ///   `simulatorCount` is how many simulators lose their runtime as a result.
    func confirmRuntimeDeletion(runtimeCount: Int, totalBytes: Int64, simulatorCount: Int) -> Bool
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

    func confirmRuntimeDeletion(runtimeCount: Int, totalBytes: Int64, simulatorCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = runtimeCount == 1
            ? "Delete this simulator runtime?"
            : "Delete \(runtimeCount) simulator runtimes?"

        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        var text = "This frees up about \(size). A deleted runtime can only be restored by downloading it again."
        if simulatorCount > 0 {
            text += simulatorCount == 1
                ? " 1 simulator uses it and will become unavailable; Cleanup Simulators will then list it."
                : " \(simulatorCount) simulators use it and will become unavailable; Cleanup Simulators will then list them."
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)

        return alert.runModal() == .alertFirstButtonReturn
    }
}
