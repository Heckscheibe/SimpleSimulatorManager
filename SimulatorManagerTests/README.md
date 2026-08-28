# Testing Documentation for SimulatorManager

## Overview

This document describes the testing approach and architecture for the SimulatorManager project, specifically focusing on the `SimulatorManagerViewModel` and its dependencies.

## Testing Architecture

### Protocols and Abstractions

To enable effective unit testing, we've introduced protocol abstractions for the main dependencies:

1. **DeviceManagerProtocol**: Defines the interface for device management functionality
2. **DeviceAppMonitoringServiceProtocol**: Defines the interface for app monitoring services

### Mock Implementations

#### MockDeviceManager
- Implements `DeviceManagerProtocol`
- Provides controllable test data via `CurrentValueSubject` publishers
- Tracks method calls for verification
- Includes helper methods for test setup and state management

#### MockDeviceAppMonitoringService
- Implements `DeviceAppMonitoringServiceProtocol`
- Tracks method calls for verification
- Lightweight mock focused on behavioral verification

### Test Data Helpers

The `TestDataHelpers` enum provides factory methods for creating test data:
- Mock devices with configurable properties
- Mock device types for different platforms
- Mock apps and app changes
- Pre-configured test scenarios

## Test Structure

### SimulatorManagerViewModelTests
Primary test suite covering:
- Initialization and binding behavior
- Reactive data flow through Combine publishers
- Integration between view model and dependencies
- Memory management verification

### SimulatorManagerViewModelEdgeCaseTests
Extended test suite covering:
- Edge cases and error conditions
- Performance scenarios (large datasets, rapid updates)
- Concurrent access patterns
- Platform-specific scenarios

### DeviceManagerProtocolTests
Protocol conformance and integration tests:
- Verification that concrete types conform to protocols
- Mock behavior validation
- Integration testing with actual protocol instances

## Testing Patterns

### Waiting for asynchronous state

State that arrives through Combine (`.receive(on: DispatchQueue.main)`) or through a detached
`Task` has not landed by the time the triggering call returns. Wait for the condition itself — a
fixed `Task.sleep` is a guess that a loaded machine or a parallel test run can outrun, which turns
into an intermittent failure that is hard to reproduce.

```swift
// Set up mock data
mockDeviceManager.setMockDevices(testDevices)

// Wait for the state the view model actually exposes, with a generous timeout
await waitUntil { viewModel.devices.count == expectedCount }

#expect(viewModel.devices.count == expectedCount)
```

`CleanupSimulatorsViewModelTests` polls the view model's own progress flags
(`isLoadingCleanupCandidates`, `deletingCandidateIDs`); `SettingsMenuVisibilityTests` drains
main-queue turns for Combine bindings. Pick whichever matches the layer under test.

### Never index a collection whose size has not been proven

`#expect` **records a failure and keeps going**, so it cannot guard a subscript. An out-of-range
`Array` subscript is a fatal Swift trap, not a recorded failure: it kills the test host process and
every test running alongside it. Use `#require`, which throws and ends only the failing test.

```swift
// Wrong — an unexpected count crashes the whole test host
#expect(groups.count == 2)
#expect(groups[0].candidates == [expectedCandidate])

// Right — a wrong count fails this test and nothing else
try #require(groups.count == 2)
#expect(groups[0].candidates == [expectedCandidate])
```

The same applies to `!`-unwrapping and `try!` in assertions.

### Call Verification
```swift
// Execute operation
mockDeviceManager.updateSpecificDevice(device)

// Verify method was called
#expect(mockDeviceManager.updateSpecificDeviceCalled)
#expect(mockDeviceManager.lastUpdatedDevice?.udid == device.udid)
```

### Concurrent Testing
```swift
await withTaskGroup(of: Void.self) { group in
    group.addTask { /* Concurrent operation 1 */ }
    group.addTask { /* Concurrent operation 2 */ }
}
```

## Benefits of This Approach

1. **Isolation**: Tests run independently of file system and external dependencies
2. **Control**: Complete control over test data and timing
3. **Speed**: Fast execution without I/O operations
4. **Reliability**: Deterministic test outcomes
5. **Coverage**: Comprehensive testing of edge cases and error conditions

## Running Tests

Tests use Swift Testing framework and can be run via:
- Xcode Test Navigator
- Command line: `swift test`
- Xcode menu: Product → Test

## Best Practices

1. **Use factory methods** from TestDataHelpers for consistent test data
2. **Wait for a condition**, not for a duration, when asserting on asynchronous state
3. **Guard every subscript** with `try #require` — a trap takes the whole test host down
4. **Reset mock state** between tests to ensure isolation
5. **Test both happy path and edge cases**
6. **Verify both state changes and method calls**
7. **Use meaningful test names** that describe the scenario being tested

## File Organization

```
SimulatorManagerTests/
├── Mocks/
│   ├── MockDeviceManager.swift
│   └── MockDeviceAppMonitoringService.swift
├── Helpers/
│   └── TestDataHelpers.swift
├── ViewModels/
│   ├── SimulatorManagerViewModelTests.swift
│   └── SimulatorManagerViewModelEdgeCaseTests.swift
└── Protocols/
    └── DeviceManagerProtocolTests.swift
```

This structure provides comprehensive test coverage while maintaining clean separation of concerns and enabling reliable, fast-running tests.
