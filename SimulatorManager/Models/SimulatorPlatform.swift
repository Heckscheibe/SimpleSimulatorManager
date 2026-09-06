//
//  SimulatorPlatform.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 29.08.25.
//

import Foundation

enum SimulatorPlatform {
    case iPhone
    case iPad
    case watch
    case appleTV
    case visionPro
    case iPodTouch
    
    init(from deviceTypeIdentifier: String) {
        if deviceTypeIdentifier.contains("iPhone") {
            self = .iPhone
        } else if deviceTypeIdentifier.contains("iPad") {
            self = .iPad
        } else if deviceTypeIdentifier.contains("Apple-Vision-Pro") {
            self = .visionPro
        } else if deviceTypeIdentifier.contains("Apple-TV") {
            self = .appleTV
        } else if deviceTypeIdentifier.contains("Apple-Watch") {
            self = .watch
        } else {
            self = .iPodTouch
        }
    }
}

extension SimulatorPlatform {
    /// SF Symbol representing the platform, for rows that show a device rather than an app.
    var iconName: String {
        switch self {
        case .iPhone:
            return "iphone.gen3"
        case .iPad:
            return "ipad"
        case .watch:
            return "applewatch"
        case .appleTV:
            return "appletv"
        case .visionPro:
            return "vision.pro"
        case .iPodTouch:
            return "ipodtouch"
        }
    }
}
