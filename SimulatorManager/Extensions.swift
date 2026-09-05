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

// MARK: - Shell-Safe Paths

extension String {
    /// The string in a form that pastes into a terminal and resolves as-is.
    ///
    /// Ordinary CoreSimulator paths contain nothing the shell interprets and come back unchanged,
    /// so what lands on the clipboard still reads like a plain path. Anything else — a space in an
    /// app group name, a quote in a device name — is backslash-escaped so the path stays a single
    /// argument.
    var shellEscaped: String {
        let additionalSafeCharacters = CharacterSet(charactersIn: "_-./+:,=@%")
        let isSafe: (Unicode.Scalar) -> Bool = { scalar in
            CharacterSet.alphanumerics.contains(scalar) || additionalSafeCharacters.contains(scalar)
        }

        guard unicodeScalars.contains(where: { !isSafe($0) }) else {
            return self
        }

        return unicodeScalars
            .map { isSafe($0) ? String($0) : "\\" + String($0) }
            .joined()
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
