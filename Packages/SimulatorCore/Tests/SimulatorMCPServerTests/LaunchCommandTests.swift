import Foundation
@testable import SimulatorMCPServer
import Testing

@Suite("Launch command and server identity")
struct LaunchCommandTests {
    @Test("No arguments runs with every gate closed")
    func noArguments() {
        #expect(LaunchCommand.parse([]) == .run(ServerOptions(allowUserDefaults: false, allowDestructive: false)))
    }

    @Test("Each flag opens its own gate")
    func flags() {
        #expect(LaunchCommand.parse(["--allow-user-defaults"]) == .run(ServerOptions(allowUserDefaults: true)))
        #expect(LaunchCommand.parse(["--allow-destructive"]) == .run(ServerOptions(allowDestructive: true)))
        #expect(LaunchCommand.parse(["--allow-destructive", "--allow-user-defaults"]) == .run(.allFlags))
    }

    @Test("--version and --help win over flags")
    func versionAndHelp() {
        #expect(LaunchCommand.parse(["--allow-destructive", "--version"]) == .version)
        #expect(LaunchCommand.parse(["--help"]) == .help)
        #expect(LaunchCommand.parse(["-h"]) == .help)
    }

    @Test("An unknown argument is rejected rather than ignored")
    func unknownArgument() {
        #expect(LaunchCommand.parse(["--allow-everything"]) == .invalid(argument: "--allow-everything"))
        #expect(LaunchCommand.parse(["--allow-user-defaults", "--allow-destructve"]) == .invalid(argument: "--allow-destructve"))
    }

    @Test("The usage names both flags")
    func usageNamesFlags() {
        #expect(LaunchCommand.usage.contains("--allow-user-defaults"))
        #expect(LaunchCommand.usage.contains("--allow-destructive"))
    }

    @Test("The server version matches the app's MARKETING_VERSION")
    func versionMatchesMarketingVersion() throws {
        let projectFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SimulatorMCPServerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SimulatorCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("SimulatorManager.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectFile, encoding: .utf8)

        let versions = Set(project.matches(of: #/MARKETING_VERSION = ([^;]+);/#).map { String($0.output.1) })

        #expect(versions == [SimulatorMCPServer.version])
    }
}
