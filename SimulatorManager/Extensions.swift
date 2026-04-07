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

// MARK: - Shell Command Execution

extension Process {
    /// Execute a shell command and return the result
    @discardableResult
    static func execute(command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = arguments.isEmpty ? ["-c", command] : arguments
        process.executableURL = arguments.isEmpty ? URL(fileURLWithPath: "/bin/sh") : URL(fileURLWithPath: command)

        try process.run()

        // Drain the pipe before waiting for termination to avoid deadlocking
        // when the child process produces more output than fits in the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorInfo = [NSLocalizedDescriptionKey: "Command failed: \(output)"]
            throw NSError(domain: "ShellCommand", code: Int(process.terminationStatus), userInfo: errorInfo)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
