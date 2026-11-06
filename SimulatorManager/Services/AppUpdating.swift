//
//  AppUpdating.swift
//  SimulatorManager
//

import AppKit
import Foundation

/// What the menu and the settings window need from the app updater, without Sparkle.
///
/// The menu is rendered from this protocol so its states can be tested without a live
/// `SPUUpdater`. The concrete type is ``SparkleAppUpdater``.
@MainActor
protocol AppUpdating: ObservableObject {
    /// `false` while a check or an update session is running. Mirrors `SPUUpdater.canCheckForUpdates`
    /// rather than keeping a separate "in flight" flag.
    var canCheckForUpdates: Bool { get }

    /// The version of an update Sparkle found in the background and did not put on screen, because
    /// the user was not looking at the app. `nil` when there is nothing waiting.
    var pendingUpdateVersion: String? { get }

    /// Whether Sparkle checks on its own schedule. Read from and written to the updater itself, see
    /// ``SparkleAppUpdater``.
    var automaticallyChecksForUpdates: Bool { get set }

    /// Checks now, showing Sparkle's UI — including for "up to date" and for failures — or, when an
    /// update is pending, bringing it on screen.
    func checkForUpdates()
}

// MARK: - Activation

/// Brings the app forward so Sparkle's windows are not opened behind whatever the user is using.
@MainActor
protocol AppActivating {
    func activate()
    func deactivate()
}

/// This is an `LSUIElement` app: no Dock icon, and never frontmost on its own. Without activating,
/// every Sparkle window would open behind the active app with nothing to click to reach it.
struct NSAppActivator: AppActivating {
    func activate() {
        // `activate(ignoringOtherApps:)` is deprecated and a no-op since macOS 14; activation is
        // cooperative now and is granted while the user is interacting with the app.
        NSApp.activate()
    }

    func deactivate() {
        // Do not pull focus out of another window of ours (the settings window, say).
        guard NSApp.keyWindow == nil else {
            return
        }

        NSApp.deactivate()
    }
}

/// The decisions behind Sparkle's `SPUStandardUserDriverDelegate` callbacks, kept free of Sparkle
/// types so they can be tested.
///
/// A scheduled check finds updates while the user is somewhere else. Activating the app then would
/// be refused or, worse, steal focus, so a scheduled update is only put on screen when the user is
/// already in the app; otherwise it becomes ``pendingUpdateVersion``, which the menu offers as an
/// "Update Available" row (Sparkle's "gentle reminder").
@MainActor
final class UpdatePresentationCoordinator: ObservableObject {
    @Published private(set) var pendingUpdateVersion: String?

    private let activator: AppActivating
    private var didActivateForSession = false

    init(activator: AppActivating = NSAppActivator()) {
        self.activator = activator
    }

    /// Brings the app forward ahead of a window the user asked for, such as a manual check's
    /// "You're up to date", which is not an update and so never reaches ``willShowUpdate``.
    func activateForUserInitiatedCheck() {
        activate()
    }

    /// Answer for `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`.
    func shouldShowScheduledUpdate(inImmediateFocus: Bool) -> Bool {
        inImmediateFocus
    }

    /// Mirrors `standardUserDriverWillHandleShowingUpdate`. `sparkleShowsUpdate` is `false` when we
    /// declined a scheduled update above and are responsible for reminding the user.
    func willShowUpdate(version: String, sparkleShowsUpdate: Bool) {
        if sparkleShowsUpdate {
            pendingUpdateVersion = nil
            activate()
        } else {
            pendingUpdateVersion = version
        }
    }

    /// The user looked at the update, whether or not they acted on it.
    func userDidReceiveAttention() {
        pendingUpdateVersion = nil
    }

    func sessionWillFinish() {
        pendingUpdateVersion = nil

        guard didActivateForSession else {
            return
        }

        didActivateForSession = false
        activator.deactivate()
    }

    private func activate() {
        didActivateForSession = true
        activator.activate()
    }
}
