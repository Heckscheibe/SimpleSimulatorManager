//
//  SparkleAppUpdater.swift
//  SimulatorManager
//

import Combine
import Foundation
import Sparkle

/// Owns the one `SPUUpdater` of the app.
///
/// Create it once, at app level. `MenuBarExtra` rebuilds its content every time the menu opens, so
/// anything created from a view would start a new updater — and a new schedule — each time.
@MainActor
final class SparkleAppUpdater: NSObject, ObservableObject, AppUpdating {
    @Published private(set) var canCheckForUpdates = false

    var pendingUpdateVersion: String? {
        presentation.pendingUpdateVersion
    }

    /// Not mirrored into `Settings`. Sparkle owns `SUEnableAutomaticChecks` and reads and writes it
    /// in the app's standard `UserDefaults`, while `Settings` uses its own suite; a copy there
    /// would be a second source of truth that Sparkle never consults.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    private let presentation: UpdatePresentationCoordinator
    private var controller: SPUStandardUpdaterController!
    private var cancellables = Set<AnyCancellable>()

    private var updater: SPUUpdater {
        controller.updater
    }

    /// - Parameter startsUpdater: `false` keeps the updater from checking at all, for runs that
    ///   host the app without wanting it to reach for the network or open windows (the tests).
    init(startsUpdater: Bool = true, presentation: UpdatePresentationCoordinator = UpdatePresentationCoordinator()) {
        self.presentation = presentation
        super.init()

        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)

        presentation.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        if startsUpdater {
            controller.startUpdater()
        }
    }

    func checkForUpdates() {
        // Activating first is only right when Sparkle is going to show something: a check that
        // cannot start would pull the app forward and leave the activation unreleased.
        guard canCheckForUpdates || pendingUpdateVersion != nil else {
            return
        }

        presentation.activateForUserInitiatedCheck()
        updater.checkForUpdates()
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension SparkleAppUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            presentation.shouldShowScheduledUpdate(inImmediateFocus: immediateFocus)
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            presentation.willShowUpdate(version: update.displayVersionString, sparkleShowsUpdate: handleShowingUpdate)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            presentation.userDidReceiveAttention()
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            presentation.sessionWillFinish()
        }
    }
}
