//
//  InstallAgeTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 28.10.26.
//

import Foundation
import Testing
@testable import SimulatorManager
@testable import SimulatorCore

@Suite("Install age")
@MainActor
struct InstallAgeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60
    private let formatter = AppInstallAgeFormatter(locale: Locale(identifier: "en_US"))

    private func app(installedAgo: TimeInterval?, activeAgo: TimeInterval? = nil) -> MockSimulatorApp {
        var app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.weather", displayName: "Weather")
        app.bundleModifiedAt = installedAgo.map { now.addingTimeInterval(-$0) }
        app.contentModifiedAt = activeAgo.map { now.addingTimeInterval(-$0) }

        return app
    }

    // MARK: - Formatter

    @Test("An app without a bundle date has no age rather than a placeholder")
    func noBundleDateMeansNoAge() {
        #expect(formatter.age(for: app(installedAgo: nil), changeType: .installed, now: now, staleAfter: day) == nil)
    }

    @Test("Under a minute reads as just now")
    func underAMinuteIsJustNow() throws {
        let age = try #require(formatter.age(for: app(installedAgo: 20), changeType: nil, now: now, staleAfter: day))

        #expect(age.relative == "just now")
    }

    @Test("A bundle dated ahead of the clock never reads as the future")
    func futureDateIsClamped() throws {
        let age = try #require(formatter.age(for: app(installedAgo: -300), changeType: nil, now: now, staleAfter: day))

        #expect(age.relative == "just now")
        #expect(!age.isStale)
    }

    @Test("Staleness starts at the threshold")
    func stalenessBoundary() throws {
        let justUnder = try #require(formatter.age(for: app(installedAgo: day - 1), changeType: nil, now: now, staleAfter: day))
        let atThreshold = try #require(formatter.age(for: app(installedAgo: day), changeType: nil, now: now, staleAfter: day))

        #expect(!justUnder.isStale)
        #expect(atThreshold.isStale)
    }

    @Test("A longer threshold keeps an older install fresh")
    func thresholdIsConfigurable() throws {
        let age = try #require(formatter.age(for: app(installedAgo: 2 * day), changeType: nil, now: now, staleAfter: 3 * day))

        #expect(!age.isStale)
    }

    @Test("Installed and updated are told apart by the change type")
    func kindFollowsChangeType() throws {
        let installed = try #require(formatter.age(for: app(installedAgo: 600), changeType: .installed, now: now, staleAfter: day))
        let updated = try #require(formatter.age(for: app(installedAgo: 600), changeType: .updated, now: now, staleAfter: day))
        let unknown = try #require(formatter.age(for: app(installedAgo: 600), changeType: nil, now: now, staleAfter: day))

        #expect(installed.kind == .installed)
        #expect(updated.kind == .updated)
        #expect(unknown.kind == nil)
    }

    @Test("VoiceOver hears the verb, the age and the stale flag")
    func accessibilityDescription() throws {
        let age = try #require(formatter.age(for: app(installedAgo: 3 * day), changeType: .updated, now: now, staleAfter: day))

        #expect(age.accessibilityDescription.hasPrefix("updated "))
        #expect(age.accessibilityDescription.hasSuffix(", stale"))
    }

    // MARK: - Tree

    @Test("A recent app row carries its age and starts its submenu with the written-out dates")
    func recentAppRowCarriesAge() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let change = TestDataHelpers.createMockAppChange(app: app(installedAgo: 10 * day, activeAgo: 60),
                                                         changeType: .updated)
        await fixture.setRecentApps([change])

        var builder = fixture.makeBuilder()
        builder.now = now
        let nodes = builder.makeNodes()
        let row = try #require(nodes.node(withID: "recentApp.\(change.id)"))

        #expect(row.age?.kind == .updated)
        #expect(row.age?.isStale == true)
        #expect(row.accessibilityLabel.contains("updated"))
        #expect(row.accessibilityLabel.contains("stale"))

        let children = row.children
        // At the bottom, behind a rule, and none of it selectable.
        let ageRows = Array(children.suffix(4))
        #expect(ageRows.first?.kind.isDivider == true)
        #expect(ageRows.dropFirst().first?.title.hasPrefix("Updated: ") == true)
        #expect(ageRows.contains { $0.title.hasPrefix("Last active: ") })
        #expect(ageRows.last?.title.hasPrefix("Stale: ") == true)
        #expect(ageRows.allSatisfy { !$0.isSelectable })
        #expect(children.first?.id.contains(".age.") == false)
    }

    @Test("Turning the display off removes the age and the date rows")
    func ageCanBeSwitchedOff() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let change = TestDataHelpers.createMockAppChange(app: app(installedAgo: 10 * day))
        await fixture.setRecentApps([change])
        fixture.settings.showInstallAge = false

        var builder = fixture.makeBuilder()
        builder.now = now
        let row = try #require(builder.makeNodes().node(withID: "recentApp.\(change.id)"))

        #expect(row.age == nil)
        #expect(!row.children.contains { $0.id.contains(".age.") })
    }

    @Test("An app with no bundle date gets no age and no date rows")
    func appWithoutDateIsLeftAlone() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let change = TestDataHelpers.createMockAppChange(app: app(installedAgo: nil))
        await fixture.setRecentApps([change])

        var builder = fixture.makeBuilder()
        builder.now = now
        let row = try #require(builder.makeNodes().node(withID: "recentApp.\(change.id)"))

        #expect(row.age == nil)
        #expect(!row.children.contains { $0.id.contains(".age.") })
    }

    @Test("The same row turns stale as the clock advances, keeping its identity")
    func ageAdvancesWithTheClock() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let change = TestDataHelpers.createMockAppChange(app: app(installedAgo: 300))
        await fixture.setRecentApps([change])

        var earlier = fixture.makeBuilder()
        earlier.now = now
        var later = fixture.makeBuilder()
        later.now = now.addingTimeInterval(10 * day)

        let freshRow = try #require(earlier.makeNodes().node(withID: "recentApp.\(change.id)"))
        let agedRow = try #require(later.makeNodes().node(withID: "recentApp.\(change.id)"))

        #expect(freshRow.age?.isStale == false)
        #expect(agedRow.age?.isStale == true)
    }

    @Test("An update that only touched the container is not described as an update")
    func containerOnlyUpdateHasNoKind() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        var change = TestDataHelpers.createMockAppChange(app: app(installedAgo: 10 * day), changeType: .updated)
        change.replacedBundle = false
        await fixture.setRecentApps([change])

        var builder = fixture.makeBuilder()
        builder.now = now
        let row = try #require(builder.makeNodes().node(withID: "recentApp.\(change.id)"))

        #expect(row.age?.kind == nil)
        #expect(row.children.contains { $0.title.hasPrefix("Last installed: ") })
    }

    @Test("The stale line follows the verb of the line above it")
    func staleLineMatchesTheVerb() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let change = TestDataHelpers.createMockAppChange(app: app(installedAgo: 10 * day), changeType: .updated)
        await fixture.setRecentApps([change])

        var builder = fixture.makeBuilder()
        builder.now = now
        let row = try #require(builder.makeNodes().node(withID: "recentApp.\(change.id)"))
        let staleRow = try #require(row.children.first { $0.id.hasSuffix(".age.stale") })

        #expect(staleRow.title.hasPrefix("Stale: updated more than "))
        #expect(staleRow.title.contains("7 days"))
    }

    @Test("A flyout is redrawn when only the age on a row changed")
    func flyoutSignatureCoversTheAge() {
        let formatter = AppInstallAgeFormatter(locale: Locale(identifier: "en_US"))
        let freshAge = formatter.age(for: app(installedAgo: 300), changeType: nil, now: now, staleAfter: day)
        let laterAge = formatter.age(for: app(installedAgo: 600), changeType: nil, now: now, staleAfter: day)
        #expect(freshAge != laterAge)

        func level(_ age: AppInstallAge?) -> MenuPanelLevel {
            MenuPanelLevel(title: nil, nodes: [.submenu(id: "app", title: "Weather", age: age, children: [])], depth: 1)
        }

        let frame = CGRect(x: 0, y: 0, width: 300, height: 22)

        #expect(MenuFlyoutController.signature(of: level(freshAge), anchoredTo: frame, hangingOffFrame: frame)
            != MenuFlyoutController.signature(of: level(laterAge), anchoredTo: frame, hangingOffFrame: frame))
    }

    @Test("Day counts are spelled out once, singular and plural")
    func dayCountText() {
        #expect(AppInstallAgeFormatter.dayCount(1).contains("1"))
        #expect(AppInstallAgeFormatter.dayCount(1) != AppInstallAgeFormatter.dayCount(7))
        #expect(AppInstallAgeFormatter.dayCount(of: 7 * day) == AppInstallAgeFormatter.dayCount(7))
    }

    // MARK: - Settings

    @Test("Defaults: ages on, stale after seven days")
    func settingsDefaults() {
        let suite = "InstallAgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        let settings = Settings(userDefaults: defaults)

        #expect(settings.showInstallAge)
        #expect(settings.staleAfterDays == 7)
        #expect(settings.staleAfterInterval == 7 * 24 * 60 * 60)
    }

    @Test("The threshold persists and is clamped")
    func settingsThreshold() {
        let suite = "InstallAgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        let settings = Settings(userDefaults: defaults)
        settings.staleAfterDays = 3
        #expect(Settings(userDefaults: defaults).staleAfterDays == 3)

        settings.staleAfterDays = 0
        #expect(settings.staleAfterDays == 1)

        defaults?.setValue(-4, forKey: "staleAfterDays")
        #expect(settings.staleAfterDays == 1)
    }
}
