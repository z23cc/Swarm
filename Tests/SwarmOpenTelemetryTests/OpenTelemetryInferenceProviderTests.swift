import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
import Swarm
@testable import SwarmOpenTelemetry

private struct PromptOnlyProvider: InferenceProvider {
    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        prompt
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(prompt)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: prompt)
    }
}

private struct ToolStreamingProvider: InferenceProvider, ToolCallStreamingInferenceProvider {
    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        prompt
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(prompt)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: prompt)
    }

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.outputChunk(prompt))
            continuation.finish()
        }
    }
}

private struct TwoLLMCallAgent: AgentRuntime {
    let provider: any InferenceProvider

    var tools: [any AnyJSONTool] { [] }
    var instructions: String { "test" }
    var configuration: AgentConfiguration { .default.name("two-call-agent") }
    var inferenceProvider: (any InferenceProvider)? { provider }

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        let provider = AgentEnvironmentValues.current.inferenceProviderTransform?(provider) ?? provider
        _ = try await provider.generate(prompt: input, options: .default)
        _ = try await provider.generate(prompt: "\(input) again", options: .default)
        return AgentResult(output: "done", iterationCount: 1)
    }

    func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}
}

private final class RecordingSpanExporter: SpanExporter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpanData] = []

    var spans: [SpanData] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        lock.lock()
        storage.append(contentsOf: spans)
        lock.unlock()
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {}
}

@Test("OpenTelemetry wrapper does not add unsupported tool streaming")
func openTelemetryWrapperDoesNotAddUnsupportedToolStreaming() {
    let wrapped = OpenTelemetryInferenceProvider(PromptOnlyProvider())

    #expect(!(wrapped is any ToolCallStreamingInferenceProvider))
    #expect(!wrapped.capabilities.contains(.streamingToolCalls))
}

@Test("OpenTelemetry wrapper preserves supported tool streaming")
func openTelemetryWrapperPreservesSupportedToolStreaming() {
    let wrapped = OpenTelemetryInferenceProvider(ToolStreamingProvider())
    let provider: any InferenceProvider = wrapped

    #expect(provider is any ToolCallStreamingInferenceProvider)
    #expect(wrapped.capabilities.contains(.streamingToolCalls))
}

@Test("Raw provider OpenTelemetry instrumentation is public API")
func rawProviderOpenTelemetryInstrumentationIsPublicAPI() async throws {
    let provider = PromptOnlyProvider().instrumentedWithOpenTelemetry()

    let output = try await provider.generate(prompt: "hello", options: .default)

    #expect(output == "hello")
}

@Test("Erased OpenTelemetry wrapper preserves prompt-only tool streaming shape")
func erasedOpenTelemetryWrapperPreservesPromptOnlyToolStreamingShape() {
    let wrapped = OpenTelemetryAnyInferenceProvider(
        ToolStreamingProvider(),
        tracer: OpenTelemetry.instance.tracerProvider.get(instrumentationName: "test.llm"),
        captureContent: false
    )

    #expect(wrapped is any ToolCallStreamingInferenceProvider)
    #expect(!(wrapped is any ConversationInferenceProvider))
    #expect(!(wrapped is any ToolCallStreamingConversationInferenceProvider))
    #expect(!InferenceProviderCapabilities.resolved(for: wrapped).contains(.conversationMessages))
    #expect(InferenceProviderCapabilities.resolved(for: wrapped).contains(.streamingToolCalls))
}

@Test("Agent OpenTelemetry wrapper creates one parent trace for multiple LLM calls")
func agentOpenTelemetryWrapperCreatesOneParentTraceForMultipleLLMCalls() async throws {
    let exporter = RecordingSpanExporter()
    let tracerProvider = TracerProviderBuilder()
        .add(
            spanProcessor: SimpleSpanProcessor(spanExporter: exporter)
                .reportingOnlySampled(sampled: false)
        )
        .build()

    let agent = TwoLLMCallAgent(provider: PromptOnlyProvider())
        .instrumentedWithOpenTelemetry(
            tracer: tracerProvider.get(instrumentationName: "test.agent"),
            llmTracer: tracerProvider.get(instrumentationName: "test.llm")
        )

    _ = try await agent.run("hello")
    tracerProvider.forceFlush()

    let spans = exporter.spans
    let agentSpan = try #require(spans.first { $0.name == "swarm.agent.run two-call-agent" })
    let llmSpans = spans.filter { $0.name == "chat llm" }

    #expect(llmSpans.count == 2)
    #expect(llmSpans.allSatisfy { $0.traceId == agentSpan.traceId })
    #expect(llmSpans.allSatisfy { $0.parentSpanId == agentSpan.spanId })
}

@Test("Inference metadata snapshot exposes non-sensitive provider fields")
func inferenceMetadataSnapshotExposesProviderFields() {
    let endpoint = URL(string: "https://api.example.com/v1")
    let metadata = InferenceProviderMetadataSnapshot(
        providerName: "example",
        modelName: "example-model",
        endpointURL: endpoint
    )

    #expect(metadata.providerName == "example")
    #expect(metadata.modelName == "example-model")
    #expect(metadata.endpointURL == endpoint)
}
