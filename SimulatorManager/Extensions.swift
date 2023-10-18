//
//  Extensions.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

extension FileManager {
    func directoryExistsAtURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        _ = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}

@propertyWrapper public struct CodableIgnored<T>: Codable {
    public var wrappedValue: T?
        
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        self.wrappedValue = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        // Do nothing
    }
}

extension KeyedDecodingContainer {
    public func decode<T>(_ type: CodableIgnored<T>.Type,
                          forKey key: Self.Key) throws -> CodableIgnored<T> {
        return CodableIgnored(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode(_ value: CodableIgnored<some Any>,
                                forKey key: KeyedEncodingContainer<K>.Key) throws {
        // Do nothing
    }
}
