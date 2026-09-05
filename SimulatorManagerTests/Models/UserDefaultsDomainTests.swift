//
//  UserDefaultsDomainTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 28.08.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("UserDefaultsDomain Tests")
struct UserDefaultsDomainTests {
    @Test("A preferences file name without its extension is the domain")
    func domainIsTheFileName() {
        let url = URL(fileURLWithPath: "/tmp/Library/Preferences/APMAnalyticsSuiteName.plist")

        #expect(UserDefaultsDomain.domain(ofPreferencesFileAt: url) == "APMAnalyticsSuiteName")
    }

    @Test("Suites are kept and system domains dropped")
    func systemDomainsAreDropped() {
        let domains = ["com.test.app", "APMAnalyticsSuiteName", ".GlobalPreferences", "com.apple.UIAutomation"]

        #expect(UserDefaultsDomain.appDomains(in: domains, ownDomain: "com.test.app")
            == ["APMAnalyticsSuiteName", "com.test.app"])
    }

    @Test("A container's own domain survives even when it looks system-managed")
    func ownDomainSurvives() {
        let domains = ["com.apple.mobilesafari", "com.apple.UIAutomation"]

        #expect(UserDefaultsDomain.appDomains(in: domains, ownDomain: "com.apple.mobilesafari")
            == ["com.apple.mobilesafari"])
    }

    @Test("A container holding nothing but system domains keeps them")
    func systemOnlyContainerKeepsEverything() {
        #expect(UserDefaultsDomain.appDomains(in: [".GlobalPreferences"], ownDomain: "com.test.app")
            == [".GlobalPreferences"])
    }

    @Test("An app offers the domains it wrote, and reports having UserDefaults from them")
    func appExposesItsDomains() {
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app",
                                                userDefaultsDomains: ["com.test.app", ".GlobalPreferences"])
        let withoutDomains = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app")

        #expect(app.hasUserDefaults)
        #expect(app.exportableUserDefaultsDomains == ["com.test.app"])
        #expect(!withoutDomains.hasUserDefaults)
        #expect(withoutDomains.exportableUserDefaultsDomains.isEmpty)
    }

    @Test("An app group offers the domains in its shared container")
    func appGroupExposesItsDomains() {
        let appGroup = AppGroup(identifier: "group.com.test",
                                uuid: "uuid",
                                userDefaultsDomains: ["group.com.test", "com.apple.UIAutomation"])

        #expect(appGroup.hasUserDefaults)
        #expect(appGroup.exportableUserDefaultsDomains == ["group.com.test"])
    }
}
