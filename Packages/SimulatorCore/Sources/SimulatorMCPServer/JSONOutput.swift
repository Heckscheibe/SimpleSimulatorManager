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
        try result(json: data(value))
    }

    /// A successful tool result whose text content is `json` verbatim and whose structured content
    /// holds the same document.
    static func result(json: Data) throws -> CallTool.Result {
        // Typed as optional so the non-generic initializer is chosen over the `Codable` one.
        let structuredContent: Value? = try structuredContent(fromJSON: json)

        return CallTool.Result(
            content: [.text(text: String(decoding: json, as: UTF8.self), annotations: nil, _meta: nil)],
            structuredContent: structuredContent,
            isError: false
        )
    }

    /// Parses JSON into `Value` with `JSONSerialization` rather than `Value`'s own `Decodable`
    /// conformance, which turns any string that looks like a data URL into `.data` and re-encodes
    /// it differently — structured content has to say exactly what the text says.
    static func structuredContent(fromJSON json: Data) throws -> Value {
        try value(fromJSONObject: JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed))
    }

    private static func value(fromJSONObject object: Any) -> Value {
        switch object {
        case let string as String:
            .string(string)
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            .bool(number.boolValue)
        case let number as NSNumber where CFNumberIsFloatType(number):
            .double(number.doubleValue)
        case let number as NSNumber:
            .int(number.intValue)
        case let array as [Any]:
            .array(array.map(value(fromJSONObject:)))
        case let object as [String: Any]:
            .object(object.mapValues(value(fromJSONObject:)))
        default:
            .null
        }
    }

    static func error(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}
