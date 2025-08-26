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

// MARK: - Shell Command Execution

extension Process {
    /// Execute a shell command and return the result
    @discardableResult static func execute(command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = arguments.isEmpty ? ["-c", command] : arguments
        process.executableURL = arguments.isEmpty ? URL(fileURLWithPath: "/bin/sh") : URL(fileURLWithPath: command)
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            let errorInfo = [NSLocalizedDescriptionKey: "Command failed: \(output)"]
            throw NSError(domain: "ShellCommand", code: Int(process.terminationStatus), userInfo: errorInfo)
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
