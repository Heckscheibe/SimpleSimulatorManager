import Foundation
@testable import SimulatorManager

@MainActor
final class MockPasteboard: PasteboardWriting {
    private(set) var writtenStrings: [String] = []

    var lastWrittenString: String? {
        writtenStrings.last
    }

    var didWrite: Bool {
        !writtenStrings.isEmpty
    }

    func write(_ string: String) {
        writtenStrings.append(string)
    }
}
