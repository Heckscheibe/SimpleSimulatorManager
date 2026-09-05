//
//  PropertyListJSONConverter.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation

/// Converts an arbitrary property list into pretty-printed JSON.
///
/// UserDefaults have no fixed schema, so they cannot go through `CustomPropertyListDecoder` the way
/// the app's other plists do. JSON also cannot represent every plist type, so values without a JSON
/// counterpart are mapped to a documented, readable form rather than dropped:
///
/// - `Date` becomes an ISO 8601 string
/// - `Data` becomes `{ "__type": "data", "base64": …, "byteCount": … }`
/// - non-finite numbers become `"nan"`, `"inf"` or `"-inf"`, so one odd value cannot fail the export
/// - anything else unexpected falls back to its textual description
enum PropertyListJSONConverter {
    enum ConversionError: LocalizedError {
        case notSerializable

        var errorDescription: String? {
            switch self {
            case .notSerializable:
                "The preferences could not be converted to JSON."
            }
        }
    }

    /// Key marking a value that JSON cannot express natively.
    static let typeMarkerKey = "__type"

    /// - Returns: Pretty-printed, key-sorted JSON for `propertyList`.
    static func jsonString(from propertyList: Any) throws -> String {
        let jsonObject = jsonSafeValue(propertyList)

        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw ConversionError.notSerializable
        }

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: jsonObject,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw ConversionError.notSerializable
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw ConversionError.notSerializable
        }

        return string
    }

    /// Recursively maps a property list value onto types `JSONSerialization` accepts.
    static func jsonSafeValue(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            dictionary.mapValues { jsonSafeValue($0) }
        case let dictionary as [AnyHashable: Any]:
            // Plists allow non-string keys in theory; JSON does not, so they are stringified.
            Dictionary(dictionary.map { (String(describing: $0.key), jsonSafeValue($0.value)) },
                       uniquingKeysWith: { first, _ in first })
        case let array as [Any]:
            array.map { jsonSafeValue($0) }
        case let data as Data:
            [
                typeMarkerKey: "data",
                "base64": data.base64EncodedString(),
                "byteCount": data.count
            ]
        case let date as Date:
            date.ISO8601Format(.init(includingFractionalSeconds: true))
        case let string as String:
            string
        case let number as NSNumber:
            jsonSafeNumber(number)
        default:
            String(describing: value)
        }
    }
}

private extension PropertyListJSONConverter {
    /// Booleans arrive as `NSNumber` and would otherwise serialise as `0`/`1`, and non-finite
    /// doubles would make `JSONSerialization` throw for the whole document.
    static func jsonSafeNumber(_ number: NSNumber) -> Any {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return number.boolValue
        }

        let double = number.doubleValue
        guard !double.isFinite else {
            return number
        }
        guard !double.isNaN else {
            return "nan"
        }

        return double > 0 ? "inf" : "-inf"
    }
}
