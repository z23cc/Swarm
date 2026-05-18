import Swarm
import XCTest

@Tool("Adds two numbers")
private struct IntegrationAddTool {
    @Parameter("First number")
    var a: Int = 0

    @Parameter("Second number")
    var b: Int = 0

    func execute() async throws -> Int {
        a + b
    }
}

@Tool("Greets a user")
private struct IntegrationGreetTool {
    @Parameter("User name")
    var userName: String = ""

    @Parameter("Greeting style", default: "formal")
    var style: String = "formal"

    func execute() async throws -> String {
        style == "casual" ? "Hey \(userName)!" : "Hello, \(userName)."
    }
}

/// Integration tests that compile and execute macro-generated tools through
/// the public Swarm runtime protocols.
final class MacroIntegrationTests: XCTestCase {
    func testToolMacroIntegrationExecutesThroughAnyJSONToolAdapter() async throws {
        let tool = IntegrationAddTool().asAnyJSONTool()

        XCTAssertEqual(tool.name, "integration_add")
        XCTAssertEqual(tool.description, "Adds two numbers")
        XCTAssertEqual(tool.parameters.map(\.name), ["a", "b"])

        let result = try await tool.execute(arguments: ["a": .int(20), "b": .int(22)])
        XCTAssertEqual(result, .int(42))
    }

    func testToolWithOptionalParametersUsesDefaultAndOverride() async throws {
        let tool = IntegrationGreetTool().asAnyJSONTool()

        let defaultResult = try await tool.execute(arguments: ["userName": .string("Ava")])
        XCTAssertEqual(defaultResult, .string("Hello, Ava."))

        let casualResult = try await tool.execute(arguments: [
            "userName": .string("Ava"),
            "style": .string("casual")
        ])
        XCTAssertEqual(casualResult, .string("Hey Ava!"))
    }

    func testToolParameterValidationThrowsForInvalidParameterType() async throws {
        let tool = IntegrationAddTool().asAnyJSONTool()

        do {
            _ = try await tool.execute(arguments: ["a": .string("not an int"), "b": .int(1)])
            XCTFail("Expected invalid parameter type to throw")
        } catch let error as AgentError {
            guard case .invalidToolArguments = error else {
                XCTFail("Expected invalidToolArguments, got \(error)")
                return
            }
        }
    }

    func testMacroGeneratedToolWorksInAgentBuilder() throws {
        let agent = try Agent("Use generated tools.") {
            IntegrationAddTool()
            IntegrationGreetTool()
        }

        XCTAssertEqual(agent.tools.map(\.name), ["integration_add", "integration_greet"])
    }
}
