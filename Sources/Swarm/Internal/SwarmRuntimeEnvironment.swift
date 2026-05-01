import Foundation

enum SwarmRuntimeEnvironment {
    static var isRunningTests: Bool {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil
        {
            return true
        }

        let arguments = processInfo.arguments.joined(separator: " ").lowercased()
        if arguments.contains("xctest") ||
            arguments.contains("swiftpm-testing-helper") ||
            arguments.contains("swift-testing")
        {
            return true
        }

        let bundlePath = Bundle.main.bundlePath.lowercased()
        if bundlePath.hasSuffix(".xctest") ||
            bundlePath.contains(".xctest/") ||
            bundlePath.contains("swiftpm-testing-helper")
        {
            return true
        }

        return NSClassFromString("XCTestCase") != nil
    }
}
