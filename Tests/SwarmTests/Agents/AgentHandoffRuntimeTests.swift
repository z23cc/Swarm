import Foundation
@testable import Swarm
import Testing

@Suite("Agent handoff runtime")
struct AgentHandoffRuntimeTests {
    @Test("Disabled handoffs are not advertised as tools")
    func disabledHandoffsAreNotAdvertisedAsTools() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(content: "done", finishReason: .completed),
        ])
        let target = RecordingHandoffReceiver(name: "target-agent")
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            when: { _, _ in false }
        )
        let regularTool = MockTool(name: "regular_tool", description: "A regular callable tool")
        let agent = try Agent(
            tools: [regularTool],
            instructions: "Route only when enabled.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        _ = try await agent.run("do not route")

        let toolCalls = await provider.toolCallMessageCalls
        #expect(toolCalls.count == 1)
        let toolNames = toolCalls[0].tools.map(\.name)
        #expect(toolNames.contains("regular_tool"))
        #expect(!toolNames.contains("handoff_to_target"))
        #expect(await target.runInputs.isEmpty)
        #expect(await target.handoffRequests.isEmpty)
    }

    @Test("Runtime handoff executes callbacks transform and nested history")
    func runtimeHandoffExecutesCallbacksTransformAndNestedHistory() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("needs specialist")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffReceiver(name: "target-agent")
        let callbackRecorder = HandoffCallbackRecorder()
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            onTransfer: { context, data in
                await callbackRecorder.recordTransfer(data)
                await context.set("transfer_seen", value: .string(data.input))
            },
            transform: { data in
                HandoffInputData(
                    sourceAgentName: data.sourceAgentName,
                    targetAgentName: data.targetAgentName,
                    input: "transformed: \(data.input)",
                    context: data.context,
                    metadata: data.metadata.merging(["transformed": .bool(true)]) { _, new in new }
                )
            },
            when: { context, _ in
                context.originalInput.contains("route")
            },
            nestHandoffHistory: true
        )
        let agent = try Agent(
            tools: [],
            instructions: "Route to target when needed.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        let result = try await agent.run("please route this")

        #expect(result.output == "handled transformed: please route this")
        #expect(await callbackRecorder.transferCount == 1)
        #expect(await callbackRecorder.lastTransfer?.input == "please route this")

        let requests = await target.handoffRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.sourceAgentName == "source-agent")
        #expect(request.targetAgentName == "target-agent")
        #expect(request.input == "transformed: please route this")
        #expect(request.reason == "needs specialist")
        #expect(request.context["transformed"] == .bool(true))

        let snapshots = await target.contextSnapshots
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        #expect(snapshot["transfer_seen"] == .string("please route this"))

        let nestedMessages = await target.contextMessages
        #expect(nestedMessages.count == 1)
        let messages = try #require(nestedMessages.first)
        #expect(messages.contains { $0.content == "please route this" })
    }

    @Test("Handoff tool call is recorded on parent result")
    func handoffToolCallIsRecordedOnParentResult() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])
        let target = RecordingHandoffReceiver(name: "target-agent")
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target"
        )
        let agent = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        let result = try await agent.run("route this")

        let handoffCall = try #require(result.toolCalls.first)
        #expect(handoffCall.toolName == "handoff_to_target")
        #expect(handoffCall.providerCallId == "call_handoff")
        #expect(handoffCall.arguments["reason"] == .string("delegate"))

        let handoffResult = try #require(result.toolResults.first)
        #expect(handoffResult.callId == handoffCall.id)
        #expect(handoffResult.isSuccess)
        #expect(handoffResult.output == .string("handled route this"))
    }
}

private actor RecordingHandoffReceiver: HandoffReceiver {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Record handoff requests"
    nonisolated let configuration: AgentConfiguration
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil
    nonisolated let inputGuardrails: [any InputGuardrail] = []
    nonisolated let outputGuardrails: [any OutputGuardrail] = []
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private(set) var runInputs: [String] = []
    private(set) var handoffRequests: [HandoffRequest] = []
    private(set) var contextSnapshots: [[String: SendableValue]] = []
    private(set) var contextMessages: [[MemoryMessage]] = []

    init(name: String) {
        configuration = AgentConfiguration(name: name, defaultTracingEnabled: false)
    }

    func run(_ input: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        runInputs.append(input)
        return AgentResult(output: "handled \(input)")
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: "handled \(input)"))))
            continuation.finish()
        }
    }

    func cancel() async {}

    func handleHandoff(_ request: HandoffRequest, context: AgentContext) async throws -> AgentResult {
        handoffRequests.append(request)
        contextSnapshots.append(await context.snapshot)
        contextMessages.append(await context.getMessages())
        return AgentResult(output: "handled \(request.input)")
    }
}

private actor HandoffCallbackRecorder {
    private(set) var transferCount = 0
    private(set) var lastTransfer: HandoffInputData?

    func recordTransfer(_ data: HandoffInputData) {
        transferCount += 1
        lastTransfer = data
    }
}
