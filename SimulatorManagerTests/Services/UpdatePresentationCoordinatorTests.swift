//
//  UpdatePresentationCoordinatorTests.swift
//  SimulatorManagerTests
//

import Testing
@testable import SimulatorManager

@MainActor
@Suite("UpdatePresentationCoordinator")
struct UpdatePresentationCoordinatorTests {
    private let activator = MockAppActivator()
    private let coordinator: UpdatePresentationCoordinator

    init() {
        coordinator = UpdatePresentationCoordinator(activator: activator)
    }

    @Test("A scheduled update is only shown unprompted when the user is already in the app")
    func scheduledUpdateNeedsImmediateFocus() {
        #expect(coordinator.shouldShowScheduledUpdate(inImmediateFocus: true))
        #expect(!coordinator.shouldShowScheduledUpdate(inImmediateFocus: false))
    }

    @Test("The app is activated before Sparkle shows an update")
    func activatesBeforeShowingAnUpdate() {
        coordinator.willShowUpdate(version: "1.5.0", sparkleShowsUpdate: true)

        #expect(activator.activateCount == 1)
        #expect(coordinator.pendingUpdateVersion == nil)
    }

    @Test("A scheduled update Sparkle does not show becomes a pending reminder without stealing focus")
    func declinedScheduledUpdateBecomesAReminder() {
        coordinator.willShowUpdate(version: "1.5.0", sparkleShowsUpdate: false)

        #expect(activator.activateCount == 0)
        #expect(coordinator.pendingUpdateVersion == "1.5.0")
    }

    @Test("Looking at the reminder clears it")
    func attentionClearsTheReminder() {
        coordinator.willShowUpdate(version: "1.5.0", sparkleShowsUpdate: false)
        coordinator.userDidReceiveAttention()

        #expect(coordinator.pendingUpdateVersion == nil)
    }

    @Test("A user-initiated check activates the app, for the windows that are not updates")
    func userInitiatedCheckActivates() {
        coordinator.activateForUserInitiatedCheck()

        #expect(activator.activateCount == 1)
    }

    @Test("Finishing a session drops the activation it took, and only that")
    func finishingDropsTheActivation() {
        coordinator.sessionWillFinish()
        #expect(activator.deactivateCount == 0)

        coordinator.willShowUpdate(version: "1.5.0", sparkleShowsUpdate: true)
        coordinator.sessionWillFinish()
        #expect(activator.deactivateCount == 1)

        coordinator.sessionWillFinish()
        #expect(activator.deactivateCount == 1)
    }

    @Test("Finishing a session clears a pending reminder")
    func finishingClearsTheReminder() {
        coordinator.willShowUpdate(version: "1.5.0", sparkleShowsUpdate: false)
        coordinator.sessionWillFinish()

        #expect(coordinator.pendingUpdateVersion == nil)
    }
}
