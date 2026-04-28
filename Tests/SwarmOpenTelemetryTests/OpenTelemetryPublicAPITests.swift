import Testing
import Swarm
import SwarmOpenTelemetry

private struct PublicAPIPromptOnlyProvider: InferenceProvider {
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

@Test("Raw provider OpenTelemetry instrumentation is available through public import")
func rawProviderOpenTelemetryInstrumentationIsAvailableThroughPublicImport() async throws {
    let provider = PublicAPIPromptOnlyProvider().instrumentedWithOpenTelemetry()

    let output = try await provider.generate(prompt: "hello", options: .default)

    #expect(output == "hello")
}
