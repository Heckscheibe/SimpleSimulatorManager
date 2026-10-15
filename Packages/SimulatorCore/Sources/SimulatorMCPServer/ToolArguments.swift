//
//  ToolArguments.swift
//  SimulatorMCPServer
//

import Foundation
import MCP

/// A tool call's arguments that do not match the tool's input schema.
struct ToolArgumentError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

/// Typed, strict access to a tool call's arguments: wrong types, empty identifiers and unknown
/// names are errors, so an agent's typo never turns into a silently ignored filter.
struct ToolArguments {
    private let values: [String: Value]

    init(_ values: [String: Value]?, allowedNames: Set<String>) throws {
        self.values = values ?? [:]

        let unknownNames = self.values.keys.filter { !allowedNames.contains($0) }.sorted()
        guard unknownNames.isEmpty else {
            let allowed = allowedNames.isEmpty ? "none" : allowedNames.sorted().joined(separator: ", ")
            throw ToolArgumentError(message: "Unknown argument \(unknownNames.joined(separator: ", ")). Allowed arguments: \(allowed).")
        }
    }

    func requiredString(_ name: String) throws -> String {
        guard let value = try optionalString(name) else {
            throw ToolArgumentError(message: "Missing required argument \(name).")
        }

        return value
    }

    /// `null` counts as absent; an empty or whitespace-only string is an error rather than absent.
    func optionalString(_ name: String) throws -> String? {
        guard let value = values[name], value != .null else {
            return nil
        }
        guard let string = value.stringValue else {
            throw ToolArgumentError(message: "Argument \(name) must be a string.")
        }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolArgumentError(message: "Argument \(name) must not be empty.")
        }

        return string
    }

    /// Accepts integral doubles too, since some clients send every JSON number as a double.
    func optionalInteger(_ name: String) throws -> Int? {
        guard let value = values[name], value != .null else {
            return nil
        }

        if let integer = value.intValue {
            return integer
        }

        if let double = value.doubleValue, double.rounded() == double, let integer = Int(exactly: double) {
            return integer
        }

        throw ToolArgumentError(message: "Argument \(name) must be an integer.")
    }

    /// `value` must be one of `allowed`, compared case-insensitively; returns the canonical spelling.
    func optionalChoice(_ name: String, from allowed: [String]) throws -> String? {
        guard let value = try optionalString(name) else {
            return nil
        }
        guard let match = allowed.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw ToolArgumentError(message: "Argument \(name) must be one of: \(allowed.joined(separator: ", ")).")
        }

        return match
    }
}
