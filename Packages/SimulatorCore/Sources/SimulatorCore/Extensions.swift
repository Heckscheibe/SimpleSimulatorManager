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

// MARK: - Blocking Work

extension DispatchQueue {
    /// Runs blocking work on this queue and bridges it back into async/await.
    ///
    /// Filesystem walks and `simctl` calls go through a dedicated queue rather than `Task.detached`,
    /// which shares the Swift concurrency cooperative pool and would starve unrelated async work.
    /// `package` so the MCP server's query service bridges the same way.
    package func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            async {
                continuation.resume(with: Result { try work() })
            }
        }
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
    public var shellEscaped: String {
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

/// Thrown by ``Process/execute(command:arguments:timeout:)`` when the child outlives its bound.
///
/// A type of its own so a caller can tell "simctl hung" from "simctl failed": the child has been
/// terminated by the time this is thrown, and there is no exit status or output to report.
struct ProcessTimeoutError: LocalizedError, Sendable {
    let commandLine: String
    let timeout: TimeInterval

    var errorDescription: String? {
        "\(commandLine) did not finish within \(Int(timeout.rounded(.up))) seconds and was stopped."
    }
}

/// How long a `simctl` call may take before it counts as hung, for the calls that have a bound.
///
/// Only calls that are quick on a healthy machine get one. `erase`, `delete`, `shutdown` and
/// `runtime delete` legitimately run for minutes on a large simulator or runtime image and stay
/// unbounded: stopping one halfway leaves its target in a worse state than waiting.
enum SimctlTimeout {
    /// `list … --json` and `runtime list -j`. Well under a second normally, but the first call
    /// after an Xcode update waits for CoreSimulatorService to start and migrate, which can take
    /// tens of seconds; a minute covers that while still ending a scan whose service is wedged.
    static let listing: TimeInterval = 60

    /// `terminate` returns in about a second. The work queue behind it is serial, so a hung call
    /// would block every later terminate, including the one before a snapshot restore.
    static let terminate: TimeInterval = 30
}

extension Process {
    /// Runs a command and returns its standard output, trimmed.
    ///
    /// With no `arguments`, `command` is a shell command line run through `/bin/sh -c`; otherwise it
    /// is the executable's path.
    ///
    /// Standard error is collected separately, so a warning a tool prints while succeeding cannot
    /// corrupt output that is parsed as JSON. It is not discarded: on a non-zero exit the thrown
    /// error's `localizedDescription` carries it (and stdout), which callers match on — see
    /// `SimulatorAppActionService.isBenignTerminationFailure`.
    ///
    /// - Parameter timeout: The longest the call may take, or `nil` to wait as long as the child
    ///   runs. When it elapses the child is terminated (and killed if it ignores that) and
    ///   ``ProcessTimeoutError`` is thrown.
    @discardableResult
    static func execute(command: String, arguments: [String] = [], timeout: TimeInterval? = nil) throws -> String {
        let process = Process()
        let standardOutput = PipeCollector()
        let standardError = PipeCollector()
        let finished = DispatchSemaphore(value: 0)

        process.standardOutput = standardOutput.pipe
        process.standardError = standardError.pipe
        process.arguments = arguments.isEmpty ? ["-c", command] : arguments
        process.executableURL = arguments.isEmpty ? URL(fileURLWithPath: "/bin/sh") : URL(fileURLWithPath: command)
        process.terminationHandler = { _ in finished.signal() }

        // Both pipes drain as data arrives, independently of each other and of termination.
        // Reading one to EOF before the other deadlocks once the child fills the second pipe's
        // buffer; waiting for exit before reading deadlocks once it fills either.
        let drained = DispatchGroup()
        standardOutput.startDraining(in: drained)
        standardError.startDraining(in: drained)

        do {
            try process.run()
        } catch {
            standardOutput.stopDraining()
            standardError.stopDraining()
            throw error
        }

        let deadline: DispatchTime = timeout.map { .now() + $0 } ?? .distantFuture

        // A grandchild that inherited a pipe can keep it open after the child exits, so the drain
        // shares the deadline too.
        guard finished.wait(timeout: deadline) == .success, drained.wait(timeout: deadline) == .success else {
            standardOutput.stopDraining()
            standardError.stopDraining()
            stop(process, finished: finished)

            let commandLine = arguments.isEmpty ? command : ([command] + arguments).joined(separator: " ")
            throw ProcessTimeoutError(commandLine: commandLine, timeout: timeout ?? 0)
        }

        let output = standardOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            let errorOutput = standardError.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = [errorOutput, output].filter { !$0.isEmpty }.joined(separator: "\n")
            let errorInfo = [NSLocalizedDescriptionKey: "Command failed: \(details)"]
            throw NSError(domain: "ShellCommand", code: Int(process.terminationStatus), userInfo: errorInfo)
        }

        return output
    }

    /// Ends a child that outlived its bound: politely first, then for good.
    private static func stop(_ process: Process, finished: DispatchSemaphore) {
        guard process.isRunning else {
            return
        }

        process.terminate()

        if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 2)
        }
    }
}

/// Collects everything written to one pipe, reading as data arrives rather than blocking a thread.
private final class PipeCollector: @unchecked Sendable {
    let pipe = Pipe()

    private let lock = NSLock()
    private var data = Data()
    private var group: DispatchGroup?

    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }

    func startDraining(in group: DispatchGroup) {
        group.enter()
        self.group = group

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else {
                return
            }

            if chunk.isEmpty {
                // EOF: every writer has closed its end.
                stopDraining()
            } else {
                lock.withLock { data.append(chunk) }
            }
        }
    }

    /// Stops reading and leaves the group, once, whether at EOF or because the caller gave up.
    func stopDraining() {
        pipe.fileHandleForReading.readabilityHandler = nil

        let group = lock.withLock {
            defer { self.group = nil }
            return self.group
        }
        group?.leave()
    }
}
