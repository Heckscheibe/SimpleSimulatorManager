//
//  JSONOutput.swift
//  SimulatorMCPServer
//

import Foundation
import MCP

/// Encodes tool results the same way everywhere: ISO 8601 dates, stable key order, unescaped paths.
enum JSONOutput {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func data(_ value: some Encodable) throws -> Data {
        try encoder().encode(value)
    }

    static func string(_ value: some Encodable) throws -> String {
        try String(decoding: data(value), as: UTF8.self)
    }

    /// A successful tool result carrying `value` both as JSON text, for clients that only read
    /// `content`, and as `structuredContent`. `value` must encode to a JSON object, as the MCP
    /// spec requires of structured content.
    static func result(_ value: some Encodable) throws -> CallTool.Result {
        let data = try data(value)
        // Decoded from the encoded JSON rather than built with `Value(_:)`, so dates keep the
        // ISO 8601 strategy in the structured copy too.
        let structuredContent: Value? = try JSONDecoder().decode(Value.self, from: data)

        return CallTool.Result(
            content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
            structuredContent: structuredContent,
            isError: false
        )
    }

    static func error(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}
