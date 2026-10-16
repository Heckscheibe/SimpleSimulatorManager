//
//  CustomPropertyListDecoder.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.23.
//

import Foundation

protocol DecodableURLContainer: Decodable {
    var url: URL? { get set }
}

class CustomPropertyListDecoder: PropertyListDecoder, Sendable, @unchecked Sendable {
    func decode<T: DecodableURLContainer>(_ type: T.Type, at url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        var object = try decode(T.self, from: data)
        object.url = url.deletingLastPathComponent()
        return object
    }
}
