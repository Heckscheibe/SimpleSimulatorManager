import Foundation
import Testing
@testable import SimulatorCore

@Suite("Process.execute Tests")
struct ProcessExecuteTests {
    private struct Decoded: Decodable, Equatable {
        let isOK: Bool
    }

    @Test("stderr written next to valid JSON on stdout does not reach the parsed output")
    func stderrNoiseDoesNotBreakJSON() throws {
        let output = try Process.execute(
            command: #"echo "warning: CoreSimulator detected a version change" >&2; echo '{"isOK": true}'"#
        )

        #expect(output == #"{"isOK": true}"#)
        #expect(try JSONDecoder().decode(Decoded.self, from: Data(output.utf8)) == Decoded(isOK: true))
    }

    @Test("A non-zero exit carries stderr and stdout in the error")
    func nonZeroExitCarriesStderr() {
        do {
            try Process.execute(command: "echo partial output; echo 'found nothing to terminate' >&2; exit 3")
            Issue.record("Expected the command to throw")
        } catch {
            #expect((error as NSError).code == 3)
            #expect(error.localizedDescription.contains("found nothing to terminate"))
            #expect(error.localizedDescription.contains("partial output"))
        }
    }

    @Test("simctl's benign termination failure is still recognised through the error text")
    func benignTerminationFailureStillMatches() {
        do {
            try Process.execute(command: """
            echo 'An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):' >&2
            echo 'Unable to lookup in current state: Shutdown' >&2
            exit 149
            """)
            Issue.record("Expected the command to throw")
        } catch {
            #expect(SimulatorAppActionService.isBenignTerminationFailure(error))
        }
    }

    @Test("More than 64 KB on both stdout and stderr does not hang", .timeLimit(.minutes(1)))
    func largeOutputOnBothPipesDoesNotHang() throws {
        // stderr first, so a reader that waits for stdout's EOF before touching stderr would leave
        // the child blocked on a full stderr pipe and never see stdout close.
        let output = try Process.execute(
            command: "head -c 200000 /dev/zero | tr '\\0' e >&2; head -c 200000 /dev/zero | tr '\\0' o"
        )

        #expect(output.count == 200_000)
        #expect(output.allSatisfy { $0 == "o" })
    }

    @Test("A child running past its bound throws the timeout error and is terminated", .timeLimit(.minutes(1)))
    func timeoutTerminatesChild() throws {
        // A duration no other process on the machine is likely to be sleeping for, so `pgrep`
        // finds only this child.
        let duration = "41.\(Int.random(in: 100_000 ... 999_999))"
        let start = Date()

        #expect(throws: ProcessTimeoutError.self) {
            try Process.execute(command: "/bin/sleep", arguments: [duration], timeout: 0.5)
        }

        #expect(Date().timeIntervalSince(start) < 10)
        #expect(try runningProcessCount(matching: "sleep \(duration)") == 0)
    }

    @Test("The timeout error reads as a sentence naming the command")
    func timeoutErrorIsReadable() {
        do {
            try Process.execute(command: "/bin/sleep", arguments: ["5"], timeout: 0.2)
            Issue.record("Expected the command to time out")
        } catch {
            #expect(error is ProcessTimeoutError)
            #expect(error.localizedDescription.contains("/bin/sleep 5"))
            #expect(error.localizedDescription.contains("did not finish"))
        }
    }

    @Test("A command finishing inside its bound returns normally")
    func commandInsideBoundSucceeds() throws {
        #expect(try Process.execute(command: "echo done", timeout: 10) == "done")
    }

    private func runningProcessCount(matching pattern: String) throws -> Int {
        let pgrep = Process()
        let pipe = Pipe()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", pattern]
        pgrep.standardOutput = pipe
        try pgrep.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .count
    }
}
