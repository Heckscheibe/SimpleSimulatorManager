import Foundation
import Testing
@testable import SimulatorManager
@testable import SimulatorCore

/// `DeviceManager` loads off the main thread at launch, so the panel can be opened before there is
/// anything to show. It says so, rather than presenting "No Recent Apps" over a menu without devices.
@Suite("MenuTreeBuilder initial load")
@MainActor
struct MenuTreeBuilderLoadingTests {
    @Test("Until the first device load publishes, a loading row stands in for No Recent Apps")
    func loadingRowBeforeTheFirstLoad() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setLoadingInitialDevices(true)
        let loadingNodes = fixture.makeBuilder().makeNodes()

        let loadingRow = try #require(loadingNodes.node(withID: "devices.loading"))
        #expect(loadingNodes.first?.id == "devices.loading")
        #expect(loadingRow.title == "Loading simulators…")
        guard case .informational = loadingRow.kind else {
            Issue.record("The loading row must be informational, not \(loadingRow.kind)")
            return
        }

        #expect(loadingRow.isSelectable == false)
        #expect(loadingRow.accessibilityLabel == "Loading simulators…")
        #expect(loadingNodes.node(withID: "recentApps.empty") == nil)

        await fixture.setLoadingInitialDevices(false)
        let loadedNodes = fixture.makeBuilder().makeNodes()

        #expect(loadedNodes.node(withID: "devices.loading") == nil)
        #expect(loadedNodes.node(withID: "recentApps.empty")?.title == "No Recent Apps")
    }

    @Test("The loading row shows even when Recent Apps is turned off")
    func loadingRowIgnoresTheRecentAppsPreference() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        fixture.settings.showRecentApps = false
        await fixture.setLoadingInitialDevices(true)

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.first?.id == "devices.loading")
    }
}
