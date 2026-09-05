//
//  MenuSearchResult.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

/// A single hit from ``MenuSearching``.
///
/// Carries everything a row needs in order to render itself and to act, so the panel never has to
/// look the underlying device or app up a second time.
struct MenuSearchResult: Identifiable {
    enum Kind {
        /// A simulator.
        case device(Device)
        /// An app together with the simulator it is installed on. The same app installed on
        /// several simulators produces one result per simulator.
        case app(app: any SimulatorApp, device: Device)
    }

    let id: String
    let kind: Kind
    /// Primary row label: the app's display name, or the device's name.
    let title: String
    /// Secondary row label. Always set for an app hit — the same app is typically installed on
    /// many simulators, so an app hit is ambiguous unless it names its device.
    let subtitle: String?
    let iconName: String
}

extension MenuSearchResult {
    /// The simulator this hit belongs to: the device itself, or the device an app is installed on.
    var device: Device {
        switch kind {
        case let .device(device):
            return device
        case let .app(_, device):
            return device
        }
    }

    /// The app this hit refers to, or `nil` for a device hit.
    var app: (any SimulatorApp)? {
        switch kind {
        case .device:
            return nil
        case let .app(app, _):
            return app
        }
    }

    static func identifier(forDeviceWithUdid udid: String) -> String {
        "device-\(udid)"
    }

    /// Takes an install identifier rather than a bundle identifier: one simulator can hold two
    /// containers sharing a bundle identifier, and two results with the same id break both the row
    /// list and selection.
    static func identifier(forAppWithInstallIdentifier installIdentifier: String, onDeviceWithUdid udid: String) -> String {
        "app-\(installIdentifier)-\(udid)"
    }
}
