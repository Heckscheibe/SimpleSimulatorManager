import Foundation

/// Waits until `condition` holds, or the timeout expires.
///
/// View models publish their state from a detached `Task` (or, in the model layer, through Combine
/// on the main queue), so nothing has landed by the time the triggering call returns. Waiting for
/// the state a view model actually exposes keeps tests deterministic: a fixed `Task.sleep` is a
/// guess that a loaded machine or a parallel test run can outrun, leaving assertions to inspect
/// state that has not arrived yet.
///
/// On timeout this returns rather than failing, so the caller's own assertions report the unmet
/// expectation with their source location.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout

    while !condition() {
        guard ContinuousClock.now < deadline else {
            return
        }

        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Yields a few main-queue turns, for state that lands through Combine or an already-scheduled
/// block rather than through a condition worth polling for.
@MainActor
func drainMainQueue(turns: Int = 3) async {
    for _ in 0 ..< turns {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
