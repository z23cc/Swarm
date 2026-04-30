// GuardrailIntegrationTests.swift
// SwarmTests
//
// Comprehensive integration tests for the complete Guardrails system
// Tests the interaction between Agents, Tools, and Guardrails

import Foundation
@testable import Swarm
import Testing

// MARK: - MockGuardrailAgent

/// Mock agent for guardrail testing
private actor MockGuardrailAgent: AgentRuntime {
    // MARK: Internal

    nonisolated let tools: [any AnyJSONTool]
    nonisolated let instructions: String
    nonisolated let configuration: AgentConfiguration
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)?
    nonisolated let tracer: (any Tracer)? = nil

    init(
        name: String = "MockAgent",
        tools: [any AnyJSONTool] = [],
        instructions: String = "Test agent",
        inferenceProvider: (any InferenceProvider)? = nil,
        responseHandler: @escaping @Sendable (String) async throws -> String = { input in "Mock response to: \(input)" }
    ) {
        self.tools = tools
        self.instructions = instructions
        configuration = AgentConfiguration(name: name)
        self.inferenceProvider = inferenceProvider
        self.responseHandler = responseHandler
    }

    func run(_ input: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) async throws -> AgentResult {
        let output = try await responseHandler(input)
        return AgentResult(output: output)
    }

    nonisolated func stream(_: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}

    // MARK: Private

    private let responseHandler: @Sendable (String) async throws -> String
}

private actor RecordingGuardrailObserver: AgentObserver {
    struct Event: Sendable, Equatable {
        let name: String
        let type: GuardrailType
        let message: String?
    }

    private(set) var events: [Event] = []

    func onGuardrailTriggered(
        context _: AgentContext?,
        guardrailName: String,
        guardrailType: GuardrailType,
        result: GuardrailResult
    ) async {
        events.append(Event(name: guardrailName, type: guardrailType, message: result.message))
    }
}

// MARK: - GuardrailIntegrationTests

@Suite("Guardrail Integration Tests")
struct GuardrailIntegrationTests {
    // MARK: - Agent + Input Guardrails

    @Test("Agent with input guardrail passed - execution proceeds normally")
    func agentWithInputGuardrailPassed() async throws {
        // Given: An agent with a passing input guardrail
        let mockProvider = MockInferenceProvider()
        await mockProvider.setResponses(["Final Answer: Success"])

        _ = MockGuardrailAgent(
            name: "TestAgent",
            inferenceProvider: mockProvider,
            responseHandler: { input in
                "Processed: \(input)"
            }
        )

        // Input guardrail that always passes
        let inputGuardrail = InputGuard("always_pass") { _, _ in
            .passed(message: "Input validation successful")
        }

        // When: Running the agent with passing guardrail
        // Note: This test assumes Agent protocol will have inputGuardrails property
        // For now, we test the guardrail runner directly
        let context = AgentContext(input: "Test query")
        let runner = GuardrailRunner()

        let results = try await runner.runInputGuardrails(
            [inputGuardrail],
            input: "Test query",
            context: context
        )

        // Then: Guardrail passes and agent would run
        #expect(results.count == 1)
        #expect(results[0].guardrailName == "always_pass")
        #expect(results[0].result.tripwireTriggered == false)
        #expect(results[0].result.message == "Input validation successful")
    }

    @Test("Agent with input guardrail triggered - execution halts with error")
    func agentWithInputGuardrailTriggered() async throws {
        // Given: An agent with a failing input guardrail
        _ = MockGuardrailAgent(name: "TestAgent")

        // Input guardrail that triggers on sensitive content
        let inputGuardrail = InputGuard("sensitive_data_blocker") { input, _ in
            if input.contains("SSN:") || input.contains("password") {
                return .tripwire(
                    message: "Sensitive data detected in input",
                    outputInfo: .dictionary([
                        "violationType": .string("PII_DETECTED"),
                        "patterns": .array([.string("SSN")])
                    ])
                )
            }
            return .passed()
        }

        // When: Running guardrail with sensitive input
        let context = AgentContext(input: "Please process SSN: 123-45-6789")
        let runner = GuardrailRunner()

        do {
            _ = try await runner.runInputGuardrails(
                [inputGuardrail],
                input: "Please process SSN: 123-45-6789",
                context: context
            )
            Issue.record("Expected GuardrailError to be thrown")
        } catch let error as GuardrailError {
            guard case let .inputTripwireTriggered(guardrailName, message, outputInfo) = error else {
                Issue.record("Unexpected GuardrailError: \(error)")
                return
            }

            #expect(guardrailName == "sensitive_data_blocker")
            #expect(message == "Sensitive data detected in input")
            #expect(outputInfo == .dictionary([
                "violationType": .string("PII_DETECTED"),
                "patterns": .array([.string("SSN")])
            ]))
        }
    }

    @Test("Agent with multiple input guardrails - executes in order")
    func agentWithMultipleInputGuardrails() async throws {
        // Given: An agent with multiple input guardrails
        actor ExecutionTracker {
            private var order: [String] = []
            func append(_ name: String) { order.append(name) }
            func getOrder() -> [String] { order }
        }

        let tracker = ExecutionTracker()

        let guardrail1 = InputGuard("length_check") { input, _ in
            await tracker.append("length_check")
            if input.count < 5 {
                return .tripwire(message: "Input too short")
            }
            return .passed()
        }

        let guardrail2 = InputGuard("format_check") { input, _ in
            await tracker.append("format_check")
            if !input.contains("?") {
                return .tripwire(message: "Input must be a question")
            }
            return .passed()
        }

        // When: Running with valid input
        let context = AgentContext(input: "What is the weather?")
        let runner = GuardrailRunner()

        let results = try await runner.runInputGuardrails(
            [guardrail1, guardrail2],
            input: "What is the weather?",
            context: context
        )

        // Then: Both guardrails execute in order
        #expect(results.count == 2)
        let executionOrder = await tracker.getOrder()
        #expect(executionOrder == ["length_check", "format_check"])
        #expect(results[0].guardrailName == "length_check")
        #expect(results[1].guardrailName == "format_check")
    }

    // MARK: - Agent + Output Guardrails

    @Test("Agent with output guardrail passed - result returned normally")
    func agentWithOutputGuardrailPassed() async throws {
        // Given: An agent with output guardrail
        let agent = MockGuardrailAgent(
            name: "OutputAgent",
            responseHandler: { _ in "Safe output content" }
        )

        let outputGuardrail = OutputGuard("output_validator") { output, _, _ in
            if output.contains("Safe") {
                return .passed(message: "Output validated successfully")
            }
            return .tripwire(message: "Output validation failed")
        }

        // When: Running output guardrail on valid output
        let result = try await agent.run("test input")
        let context = AgentContext(input: "test input")
        let runner = GuardrailRunner()

        let guardrailResults = try await runner.runOutputGuardrails(
            [outputGuardrail],
            output: result.output,
            agent: agent,
            context: context
        )

        // Then: Guardrail passes
        #expect(guardrailResults.count == 1)
        #expect(guardrailResults[0].result.tripwireTriggered == false)
        #expect(guardrailResults[0].guardrailName == "output_validator")
    }

    @Test("Agent with output guardrail triggered - throws after execution")
    func agentWithOutputGuardrailTriggered() async throws {
        // Given: An agent with output guardrail that detects inappropriate content
        let agent = MockGuardrailAgent(
            name: "OutputAgent",
            responseHandler: { _ in "This content contains profanity: damn" }
        )

        let outputGuardrail = OutputGuard("profanity_filter") { output, _, _ in
            let profaneWords = ["damn", "hell", "crap"]
            let containsProfanity = profaneWords.contains { output.lowercased().contains($0) }

            if containsProfanity {
                return .tripwire(
                    message: "Profanity detected in output",
                    outputInfo: .dictionary([
                        "category": .string("profanity"),
                        "severity": .string("low")
                    ])
                )
            }
            return .passed()
        }

        // When: Running output guardrail on inappropriate output
        let result = try await agent.run("test input")
        let context = AgentContext(input: "test input")
        let runner = GuardrailRunner()

        do {
            _ = try await runner.runOutputGuardrails(
                [outputGuardrail],
                output: result.output,
                agent: agent,
                context: context
            )
            Issue.record("Expected GuardrailError to be thrown")
        } catch let error as GuardrailError {
            guard case let .outputTripwireTriggered(guardrailName, agentName, message, outputInfo) = error else {
                Issue.record("Unexpected GuardrailError: \(error)")
                return
            }

            #expect(guardrailName == "profanity_filter")
            #expect(agentName == "OutputAgent")
            #expect(message == "Profanity detected in output")
            #expect(outputInfo == .dictionary([
                "category": .string("profanity"),
                "severity": .string("low")
            ]))
        }
    }

    // MARK: - Tool + Guardrails

    @Test("Tool execution with input guardrail - validates arguments before execution")
    func toolExecutionWithInputGuardrail() async throws {
        // Given: A tool with input guardrail
        let tool = MockTool(
            name: "calculator",
            parameters: [
                ToolParameter(name: "expression", description: "Math expression", type: .string, isRequired: true)
            ],
            result: .string("Result: 42")
        )

        let toolInputGuardrail = ClosureToolInputGuardrail(name: "argument_validator") { data in
            guard let expression = data.arguments["expression"]?.stringValue else {
                return .tripwire(message: "Missing required expression argument")
            }

            // Validate no malicious code
            if expression.contains(";") || expression.contains("eval") {
                return .tripwire(
                    message: "Potentially malicious expression detected",
                    outputInfo: .string(expression)
                )
            }
            return .passed()
        }

        // When: Running tool guardrail with valid arguments
        let agent = MockGuardrailAgent(name: "ToolAgent")
        let context = AgentContext(input: "Calculate 2+2")
        let data = ToolGuardrailData(
            tool: tool,
            arguments: ["expression": .string("2+2")],
            agent: agent,
            context: context
        )

        let runner = GuardrailRunner()
        let results = try await runner.runToolInputGuardrails([toolInputGuardrail], data: data)

        // Then: Guardrail passes
        #expect(results.count == 1)
        #expect(results[0].result.tripwireTriggered == false)
    }

    @Test("Tool execution with output guardrail - validates result after execution")
    func toolExecutionWithOutputGuardrail() async throws {
        // Given: A tool with output guardrail
        let tool = MockTool(
            name: "web_search",
            result: .dictionary([
                "results": .array([
                    .string("Safe result 1"),
                    .string("Safe result 2")
                ])
            ])
        )

        let toolOutputGuardrail = ClosureToolOutputGuardrail(name: "result_validator") { _, output in
            // Validate output structure
            guard let dict = output.dictionaryValue else {
                return .tripwire(message: "Invalid output format")
            }

            guard let results = dict["results"]?.arrayValue else {
                return .tripwire(message: "Missing results array")
            }

            // Check for empty results
            if results.isEmpty {
                return .tripwire(
                    message: "No results found",
                    outputInfo: .dictionary(["count": .int(0)])
                )
            }

            return .passed(
                message: "Results validated",
                outputInfo: .dictionary(["count": .int(results.count)])
            )
        }

        // When: Running tool output guardrail
        let agent = MockGuardrailAgent(name: "SearchAgent")
        let context = AgentContext(input: "Search for Swift")
        let toolResult = try await tool.execute(arguments: [:])
        let data = ToolGuardrailData(
            tool: tool,
            arguments: [:],
            agent: agent,
            context: context
        )

        let runner = GuardrailRunner()
        let results = try await runner.runToolOutputGuardrails([toolOutputGuardrail], data: data, output: toolResult)

        // Then: Guardrail passes with metadata
        #expect(results.count == 1)
        #expect(results[0].result.tripwireTriggered == false)
        #expect(results[0].result.message == "Results validated")
    }
}

// MARK: - GuardrailIntegrationTests Advanced

extension GuardrailIntegrationTests {
    @Test("ToolRegistry.execute() runs guardrails - full integration")
    func toolRegistryWithGuardrails() async throws {
        let inputGuardrail = ClosureToolInputGuardrail(name: "deny_secret_argument") { data in
            if data.arguments["query"]?.stringValue == "secret" {
                return .tripwire(message: "secret input blocked")
            }
            return .passed(message: "input accepted")
        }
        let outputGuardrail = ClosureToolOutputGuardrail(name: "deny_secret_output") { _, output in
            if output.stringValue == "secret result" {
                return .tripwire(message: "secret output blocked")
            }
            return .passed(message: "output accepted")
        }
        let tool = MockTool(
            name: "lookup",
            parameters: [
                ToolParameter(name: "query", description: "Query", type: .string, isRequired: true)
            ],
            inputGuardrails: [inputGuardrail],
            outputGuardrails: [outputGuardrail]
        ) { arguments in
            .string(arguments["query"]?.stringValue == "leak" ? "secret result" : "public result")
        }
        let registry = try ToolRegistry(tools: [tool])

        let allowed = try await registry.execute(toolNamed: "lookup", arguments: ["query": .string("public")])
        #expect(allowed == .string("public result"))

        await #expect(throws: GuardrailError.self) {
            _ = try await registry.execute(toolNamed: "lookup", arguments: ["query": .string("secret")])
        }

        await #expect(throws: GuardrailError.self) {
            _ = try await registry.execute(toolNamed: "lookup", arguments: ["query": .string("leak")])
        }
    }

    // MARK: - Combined Scenarios

    @Test("Agent with both input and output guardrails - full validation flow")
    func agentWithBothInputAndOutputGuardrails() async throws {
        // Given: An agent with both input and output guardrails
        let agent = MockGuardrailAgent(
            name: "FullyGuardedAgent",
            responseHandler: { input in
                "Processed and sanitized: \(input)"
            }
        )

        let inputGuardrail = InputGuard("input_sanitizer") { input, _ in
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .tripwire(message: "Empty input not allowed")
            }
            return .passed(message: "Input accepted")
        }

        let outputGuardrail = OutputGuard("output_length_checker") { output, _, _ in
            if output.count > 1000 {
                return .tripwire(
                    message: "Output too long",
                    outputInfo: .dictionary(["length": .int(output.count)])
                )
            }
            return .passed(message: "Output length acceptable")
        }

        // When: Running both guardrails
        let context = AgentContext(input: "Valid input query")
        let runner = GuardrailRunner()

        // Input guardrail check
        let inputResults = try await runner.runInputGuardrails(
            [inputGuardrail],
            input: "Valid input query",
            context: context
        )

        // Agent execution
        let result = try await agent.run("Valid input query")

        // Output guardrail check
        let outputResults = try await runner.runOutputGuardrails(
            [outputGuardrail],
            output: result.output,
            agent: agent,
            context: context
        )

        // Then: Both guardrails pass
        #expect(inputResults.count == 1)
        #expect(inputResults[0].result.tripwireTriggered == false)
        #expect(outputResults.count == 1)
        #expect(outputResults[0].result.tripwireTriggered == false)
    }

    @Test("Guardrail with agent context - context flows through validation")
    func guardrailWithAgentContext() async throws {
        // Given: A guardrail that uses context data
        let context = AgentContext(input: "Test input")
        await context.set("user_role", value: .string("admin"))
        await context.set("request_count", value: .int(5))

        actor ContextCapture {
            var value: AgentContext?
            func set(_ newValue: AgentContext?) { value = newValue }
            func get() -> AgentContext? { value }
        }
        let contextCapture = ContextCapture()
        let inputGuardrail = InputGuard("role_checker") { _, ctx in
            await contextCapture.set(ctx)

            // Check user role from context
            guard let role = await ctx?.get("user_role")?.stringValue else {
                return .tripwire(message: "No user role in context")
            }

            if role != "admin" {
                return .tripwire(message: "Insufficient permissions")
            }

            return .passed(
                message: "Role validated",
                metadata: ["role": .string(role)]
            )
        }

        // When: Running guardrail
        let runner = GuardrailRunner()
        let results = try await runner.runInputGuardrails(
            [inputGuardrail],
            input: "Admin command",
            context: context
        )

        // Then: Context is accessible in guardrail
        let captured = await contextCapture.get()
        #expect(captured != nil)
        #expect(results[0].result.tripwireTriggered == false)
        #expect(results[0].result.metadata["role"]?.stringValue == "admin")
    }

    @Test("Guardrail error propagation - errors bubble up correctly")
    func guardrailErrorPropagation() async throws {
        // Given: A guardrail that triggers
        _ = MockGuardrailAgent(name: "ErrorAgent")
        let context = AgentContext(input: "Test")

        let inputGuardrail = InputGuard("error_trigger") { _, _ in
            .tripwire(
                message: "Test error message",
                outputInfo: .dictionary([
                    "errorCode": .string("TEST_001"),
                    "timestamp": .int(1_234_567_890)
                ])
            )
        }

        // When: Running guardrail
        let runner = GuardrailRunner()

        // Then: Error is thrown with correct details
        do {
            _ = try await runner.runInputGuardrails(
                [inputGuardrail],
                input: "Test input",
                context: context
            )
            Issue.record("Expected GuardrailError to be thrown")
        } catch let error as GuardrailError {
            // Verify error details
            if case let .inputTripwireTriggered(name, message, outputInfo) = error {
                #expect(name == "error_trigger")
                #expect(message == "Test error message")
                #expect(outputInfo?.dictionaryValue?["errorCode"]?.stringValue == "TEST_001")
            } else {
                Issue.record("Wrong GuardrailError case: \(error)")
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    // MARK: - Edge Cases

    @Test("Empty guardrail arrays - execution proceeds normally")
    func emptyGuardrailArrays() async throws {
        // Given: Agent with no guardrails
        let agent = MockGuardrailAgent(
            name: "UnguardedAgent",
            responseHandler: { input in "Response: \(input)" }
        )

        let context = AgentContext(input: "Test")
        let runner = GuardrailRunner()

        // When: Running with empty guardrail arrays
        let inputResults = try await runner.runInputGuardrails(
            [],
            input: "Test input",
            context: context
        )

        let result = try await agent.run("Test input")
        let outputResults = try await runner.runOutputGuardrails(
            [],
            output: result.output,
            agent: agent,
            context: context
        )

        // Then: No guardrails run, execution succeeds
        #expect(inputResults.isEmpty)
        #expect(outputResults.isEmpty)
        #expect(result.output == "Response: Test input")
    }

    @Test("Guardrail metadata preserved - accessible after validation")
    func guardrailMetadataPreserved() async throws {
        // Given: A guardrail that sets metadata
        let context = AgentContext(input: "Test")

        let inputGuardrail = InputGuard("metadata_setter") { input, _ in
            .passed(
                message: "Validation passed with metadata",
                metadata: [
                    "validationTimestamp": .double(Date().timeIntervalSince1970),
                    "inputLength": .int(input.count),
                    "validatorVersion": .string("1.0.0"),
                    "checksPerformed": .array([
                        .string("length_check"),
                        .string("format_check"),
                        .string("content_check")
                    ])
                ]
            )
        }

        // When: Running guardrail
        let runner = GuardrailRunner()
        let results = try await runner.runInputGuardrails(
            [inputGuardrail],
            input: "Test input",
            context: context
        )

        // Then: Metadata is preserved in result
        #expect(results.count == 1)
        let metadata = results[0].result.metadata
        #expect(metadata["validatorVersion"]?.stringValue == "1.0.0")
        #expect(metadata["inputLength"]?.intValue == 10)
        #expect(metadata["checksPerformed"]?.arrayValue?.count == 3)
    }

    @Test("Parallel input guardrails - run concurrently")
    func parallelInputGuardrails() async throws {
        // Given: Multiple parallel input guardrails
        let context = AgentContext(input: "Test")

        final class IntervalTracker: @unchecked Sendable {
            struct Interval: Sendable {
                let start: ContinuousClock.Instant
                let end: ContinuousClock.Instant
            }

            private let lock = NSLock()
            private var intervals: [String: Interval] = [:]

            func record(_ name: String, start: ContinuousClock.Instant, end: ContinuousClock.Instant) {
                lock.lock()
                defer { lock.unlock() }
                intervals[name] = Interval(start: start, end: end)
            }

            func get(_ name: String) -> Interval? {
                lock.lock()
                defer { lock.unlock() }
                return intervals[name]
            }
        }

        let tracker = IntervalTracker()

        let slowGuardrail1 = InputGuard("slow1") { _, _ in
            let start = ContinuousClock.now
            try? await Task.sleep(for: .milliseconds(200))
            let end = ContinuousClock.now
            tracker.record("slow1", start: start, end: end)
            return .passed(message: "Slow check 1 complete")
        }

        let slowGuardrail2 = InputGuard("slow2") { _, _ in
            let start = ContinuousClock.now
            try? await Task.sleep(for: .milliseconds(200))
            let end = ContinuousClock.now
            tracker.record("slow2", start: start, end: end)
            return .passed(message: "Slow check 2 complete")
        }

        // When: Running parallel guardrails (using parallel runner configuration)
        let runner = GuardrailRunner(configuration: .parallel)
        let results = try await runner.runInputGuardrails(
            [slowGuardrail1, slowGuardrail2],
            input: "Test input",
            context: context
        )

        // Then: Guardrails ran in parallel (total time < sum of individual times)
        #expect(results.count == 2)
        guard let interval1 = tracker.get("slow1"), let interval2 = tracker.get("slow2") else {
            Issue.record("Missing guardrail interval data")
            return
        }

        let latestStart = max(interval1.start, interval2.start)
        let earliestEnd = min(interval1.end, interval2.end)
        #expect(latestStart < earliestEnd, "Expected parallel guardrail execution; intervals did not overlap.")
    }

    @Test("Parallel input guardrail tripwire emits observer event")
    func parallelInputGuardrailTripwireEmitsObserverEvent() async throws {
        let observer = RecordingGuardrailObserver()
        let context = AgentContext(input: "blocked")
        let guardrail = InputGuard("parallel_input_blocker") { _, _ in
            .tripwire(message: "input blocked")
        }
        let runner = GuardrailRunner(configuration: .parallel, observer: observer)

        await #expect(throws: GuardrailError.self) {
            _ = try await runner.runInputGuardrails([guardrail], input: "blocked", context: context)
        }

        let events = await observer.events
        #expect(events == [
            RecordingGuardrailObserver.Event(name: "parallel_input_blocker", type: .input, message: "input blocked")
        ])
    }

    @Test("Parallel output guardrail tripwire emits observer event")
    func parallelOutputGuardrailTripwireEmitsObserverEvent() async throws {
        let observer = RecordingGuardrailObserver()
        let context = AgentContext(input: "request")
        let agent = MockGuardrailAgent(name: "Guarded")
        let guardrail = OutputGuard("parallel_output_blocker") { _, _, _ in
            .tripwire(message: "output blocked")
        }
        let runner = GuardrailRunner(configuration: .parallel, observer: observer)

        await #expect(throws: GuardrailError.self) {
            _ = try await runner.runOutputGuardrails([guardrail], output: "blocked", agent: agent, context: context)
        }

        let events = await observer.events
        #expect(events == [
            RecordingGuardrailObserver.Event(name: "parallel_output_blocker", type: .output, message: "output blocked")
        ])
    }

    @Test("Parallel tool input guardrail tripwire emits observer event")
    func parallelToolInputGuardrailTripwireEmitsObserverEvent() async throws {
        let observer = RecordingGuardrailObserver()
        let agent = MockGuardrailAgent(name: "ToolAgent")
        let tool = MockTool(name: "lookup")
        let data = ToolGuardrailData(tool: tool, arguments: ["query": .string("blocked")], agent: agent, context: nil)
        let guardrail = ClosureToolInputGuardrail(name: "parallel_tool_input_blocker") { _ in
            .tripwire(message: "tool input blocked")
        }
        let runner = GuardrailRunner(configuration: .parallel, observer: observer)

        await #expect(throws: GuardrailError.self) {
            _ = try await runner.runToolInputGuardrails([guardrail], data: data)
        }

        let events = await observer.events
        #expect(events == [
            RecordingGuardrailObserver.Event(name: "parallel_tool_input_blocker", type: .toolInput, message: "tool input blocked")
        ])
    }

    @Test("Parallel tool output guardrail tripwire emits observer event")
    func parallelToolOutputGuardrailTripwireEmitsObserverEvent() async throws {
        let observer = RecordingGuardrailObserver()
        let agent = MockGuardrailAgent(name: "ToolAgent")
        let tool = MockTool(name: "lookup")
        let data = ToolGuardrailData(tool: tool, arguments: [:], agent: agent, context: nil)
        let guardrail = ClosureToolOutputGuardrail(name: "parallel_tool_output_blocker") { _, _ in
            .tripwire(message: "tool output blocked")
        }
        let runner = GuardrailRunner(configuration: .parallel, observer: observer)

        await #expect(throws: GuardrailError.self) {
            _ = try await runner.runToolOutputGuardrails([guardrail], data: data, output: .string("blocked"))
        }

        let events = await observer.events
        #expect(events == [
            RecordingGuardrailObserver.Event(name: "parallel_tool_output_blocker", type: .toolOutput, message: "tool output blocked")
        ])
    }
}
