//
//  PropertyListJSONConverterTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("PropertyListJSONConverter Tests")
struct PropertyListJSONConverterTests {
    @Test("Nested dictionaries and arrays survive the conversion")
    func nestedValuesAreConverted() throws {
        let propertyList: [String: Any] = [
            "name": "Test App",
            "session": [
                "identifier": "abc",
                "retries": 2,
                "tags": ["one", "two"]
            ]
        ]

        let json = try PropertyListJSONConverter.jsonString(from: propertyList)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])

        #expect(root["name"] as? String == "Test App")
        #expect(session["identifier"] as? String == "abc")
        #expect(session["retries"] as? Int == 2)
        #expect(session["tags"] as? [String] == ["one", "two"])
    }

    @Test("Booleans stay booleans instead of turning into numbers")
    func booleansKeepTheirType() throws {
        let json = try PropertyListJSONConverter.jsonString(from: ["enabled": true, "disabled": false])

        #expect(json.contains("\"enabled\" : true"))
        #expect(json.contains("\"disabled\" : false"))
    }

    @Test("Dates become ISO 8601 strings")
    func datesBecomeISO8601Strings() throws {
        let json = try PropertyListJSONConverter.jsonString(from: ["created": Date(timeIntervalSince1970: 0)])
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root["created"] as? String == "1970-01-01T00:00:00.000Z")
    }

    @Test("Data becomes a marked base64 value rather than being dropped")
    func dataBecomesBase64() throws {
        let data = Data([0x00, 0x01, 0x02])
        let json = try PropertyListJSONConverter.jsonString(from: ["token": data])
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])
        let token = try #require(root["token"] as? [String: Any])

        #expect(token[PropertyListJSONConverter.typeMarkerKey] as? String == "data")
        #expect(token["base64"] as? String == data.base64EncodedString())
        #expect(token["byteCount"] as? Int == 3)
    }

    @Test("Non-finite numbers are stringified instead of failing the whole export")
    func nonFiniteNumbersAreStringified() throws {
        let json = try PropertyListJSONConverter.jsonString(from: [
            "notANumber": Double.nan,
            "positive": Double.infinity,
            "negative": -Double.infinity,
            "ordinary": 1.5
        ])
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root["notANumber"] as? String == "nan")
        #expect(root["positive"] as? String == "inf")
        #expect(root["negative"] as? String == "-inf")
        #expect(root["ordinary"] as? Double == 1.5)
    }

    @Test("Non-string dictionary keys are stringified so the document stays valid JSON")
    func nonStringKeysAreStringified() throws {
        let propertyList: [AnyHashable: Any] = [1: "one"]

        let json = try PropertyListJSONConverter.jsonString(from: propertyList)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root["1"] as? String == "one")
    }

    @Test("Output is pretty-printed and key-sorted for readability")
    func outputIsPrettyPrintedAndSorted() throws {
        let json = try PropertyListJSONConverter.jsonString(from: ["zebra": 1, "apple": 2])
        let appleIndex = try #require(json.range(of: "apple"))
        let zebraIndex = try #require(json.range(of: "zebra"))

        #expect(json.contains("\n"))
        #expect(appleIndex.lowerBound < zebraIndex.lowerBound)
    }
}
