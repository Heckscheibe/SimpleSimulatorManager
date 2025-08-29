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
