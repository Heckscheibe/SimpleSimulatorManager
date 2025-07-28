//
//  SimulatorPlatformTests.swift
//  SimulatorManagerTests
//
//  Created by AI Assistant on 27.07.25.
//

import Testing
@testable import SimulatorManager

@Suite("SimulatorPlatform Tests") struct SimulatorPlatformTests {
    // MARK: - iPhone Platform Tests
    
    @Test("SimulatorPlatform correctly identifies iPhone devices", arguments: [
        "com.apple.CoreSimulator.SimDeviceType.iPhone-15",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Plus",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-14",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation",
        "iPhone-12-mini",
        "iPhone-13-Pro"
    ]) func testIPhoneDeviceIdentification(identifier: String) {
        let platform = SimulatorPlatform(from: identifier)
        #expect(platform == .iPhone, "Expected iPhone platform for identifier: \(identifier)")
    }
    
    // MARK: - iPad Platform Tests
    
    @Test("SimulatorPlatform correctly identifies iPad devices", arguments: [
        "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation",
        "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-4th-generation",
        "com.apple.CoreSimulator.SimDeviceType.iPad-Air-5th-generation",
        "com.apple.CoreSimulator.SimDeviceType.iPad-10th-generation",
        "com.apple.CoreSimulator.SimDeviceType.iPad-mini-6th-generation",
        "iPad-Pro-12-9",
        "iPad-Air"
    ]) func testIPadDeviceIdentification(identifier: String) {
        let platform = SimulatorPlatform(from: identifier)
        #expect(platform == .iPad, "Expected iPad platform for identifier: \(identifier)")
    }
    
    // MARK: - Apple Watch Platform Tests
    
    @Test("SimulatorPlatform correctly identifies Apple Watch devices", arguments: [
        "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-41mm",
        "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-45mm",
        "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-2-49mm",
        "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-SE-2nd-generation-40mm",
        "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-SE-2nd-generation-44mm",
        "Apple-Watch-Series-8",
        "Apple-Watch-Ultra"
    ]) func testAppleWatchDeviceIdentification(identifier: String) {
        let platform = SimulatorPlatform(from: identifier)
        #expect(platform == .watch, "Expected watch platform for identifier: \(identifier)")
    }
    
    // MARK: - Apple TV Platform Tests
    
    @Test("SimulatorPlatform correctly identifies Apple TV devices", arguments: [
        "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation",
        "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-2nd-generation",
        "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-at-1080p-3rd-generation",
        "Apple-TV-4K",
        "Apple-TV-HD"
    ]) func testAppleTVDeviceIdentification(identifier: String) {
        let platform = SimulatorPlatform(from: identifier)
        #expect(platform == .appleTV, "Expected appleTV platform for identifier: \(identifier)")
    }
    
    // MARK: - Apple Vision Pro Platform Tests
    
    @Test("SimulatorPlatform correctly identifies Apple Vision Pro devices", arguments: [
        "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro",
        "Apple-Vision-Pro-1st-generation",
        "Apple-Vision-Pro"
    ]) func testAppleVisionProDeviceIdentification(identifier: String) {
        let platform = SimulatorPlatform(from: identifier)
        #expect(platform == .visionPro, "Expected visionPro platform for identifier: \(identifier)")
    }
    
    // MARK: - iPod Touch Platform Tests
    
    @Test("SimulatorPlatform falls back to iPodTouch for unknown devices", arguments: [
        "com.apple.CoreSimulator.SimDeviceType.Unknown-Device",
        "SomeRandomDeviceType",
        "GenericSimulator",
        "",
        "com.apple.CoreSimulator.SimDeviceType.iPod-touch-7th-generation"
    ]) func testIPodTouchFallback(identifier: String) {
        let platform = SimulatorPlatform(from: identifier)
        #expect(platform == .iPodTouch, "Expected iPodTouch platform (fallback) for identifier: \(identifier)")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("SimulatorPlatform handles case sensitivity correctly", arguments: [
        ("iphone-15", SimulatorPlatform.iPodTouch), // lowercase 'i' should fall back
        ("IPHONE-15", SimulatorPlatform.iPodTouch), // uppercase should fall back
        ("iPhone-15", SimulatorPlatform.iPhone), // correct case should work
        ("ipad-pro", SimulatorPlatform.iPodTouch), // lowercase should fall back
        ("iPad-Pro", SimulatorPlatform.iPad) // correct case should work
    ]) func testCaseSensitivity(testCase: (identifier: String, expectedPlatform: SimulatorPlatform)) {
        let platform = SimulatorPlatform(from: testCase.identifier)
        #expect(
            platform == testCase.expectedPlatform,
            "Expected \(testCase.expectedPlatform) for identifier: \(testCase.identifier), got \(platform)"
        )
    }
    
    @Test("SimulatorPlatform handles partial matches correctly", arguments: [
        ("MyCustomiPhoneDevice", SimulatorPlatform.iPhone),
        ("CustomiPadSimulator", SimulatorPlatform.iPad),
        ("TestApple-WatchDevice", SimulatorPlatform.watch),
        ("CustomApple-TVSetup", SimulatorPlatform.appleTV),
        ("MyApple-Vision-ProTest", SimulatorPlatform.visionPro)
    ]) func testPartialMatches(testCase: (identifier: String, expectedPlatform: SimulatorPlatform)) {
        let platform = SimulatorPlatform(from: testCase.identifier)
        #expect(
            platform == testCase.expectedPlatform,
            "Expected \(testCase.expectedPlatform) for partial match identifier: \(testCase.identifier)"
        )
    }
    
    @Test("SimulatorPlatform handles multiple keywords correctly", arguments: [
        ("iPhone13ProMax", SimulatorPlatform.iPhone),
        ("iPadProMini", SimulatorPlatform.iPad),
        ("Apple-WatchSeries8", SimulatorPlatform.watch),
        ("Apple-TVHD", SimulatorPlatform.appleTV),
        ("Apple-Vision-ProMax", SimulatorPlatform.visionPro)
    ]) func testMultipleKeywords(testCase: (identifier: String, expectedPlatform: SimulatorPlatform)) {
        let platform = SimulatorPlatform(from: testCase.identifier)
        #expect(
            platform == testCase.expectedPlatform,
            "Expected \(testCase.expectedPlatform) for multiple keyword identifier: \(testCase.identifier)"
        )
    }
    
    @Test("SimulatorPlatform initialization is deterministic", arguments: [
        ("com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro", SimulatorPlatform.iPhone),
        ("com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch", SimulatorPlatform.iPad),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9", SimulatorPlatform.watch),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K", SimulatorPlatform.appleTV),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro", SimulatorPlatform.visionPro),
        ("unknown.identifier", SimulatorPlatform.iPodTouch)
    ]) func testDeterministicBehavior(testCase: (identifier: String, expectedPlatform: SimulatorPlatform)) {
        // Run the same initialization multiple times to ensure consistent results
        let platforms = (1 ... 10).map { _ in
            SimulatorPlatform(from: testCase.identifier)
        }
        
        // All results should be identical
        let uniquePlatforms = Set(platforms.map { "\($0)" })
        #expect(
            uniquePlatforms.count == 1,
            "Platform initialization should be deterministic for \(testCase.identifier)"
        )
        #expect(
            platforms.first == testCase.expectedPlatform,
            "Expected \(testCase.expectedPlatform) for identifier \(testCase.identifier)"
        )
    }
    
    // MARK: - Real-world Identifier Tests
    
    @Test("SimulatorPlatform handles real iOS Simulator identifiers", arguments: [
        ("com.apple.CoreSimulator.SimDeviceType.iPhone-15", SimulatorPlatform.iPhone),
        ("com.apple.CoreSimulator.SimDeviceType.iPhone-15-Plus", SimulatorPlatform.iPhone),
        ("com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro", SimulatorPlatform.iPhone),
        ("com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max", SimulatorPlatform.iPhone),
        ("com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation", SimulatorPlatform.iPad),
        ("com.apple.CoreSimulator.SimDeviceType.iPad-Air-5th-generation", SimulatorPlatform.iPad),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-41mm", SimulatorPlatform.watch),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-2-49mm", SimulatorPlatform.watch),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation", SimulatorPlatform.appleTV),
        ("com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro", SimulatorPlatform.visionPro)
    ]) func testRealSimulatorIdentifiers(testCase: (identifier: String, expectedPlatform: SimulatorPlatform)) {
        let platform = SimulatorPlatform(from: testCase.identifier)
        #expect(
            platform == testCase.expectedPlatform,
            "Real identifier \(testCase.identifier) should map to \(testCase.expectedPlatform)"
        )
    }
}
