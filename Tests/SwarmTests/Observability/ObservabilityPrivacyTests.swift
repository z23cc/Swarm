import Foundation
@testable import Swarm
import Testing

@Suite("Observability Privacy Tests")
struct ObservabilityPrivacyTests {
    @Test("public trace log sanitizer removes sensitive content from messages metadata and errors")
    func publicTraceLogSanitizerRedactsSensitiveContent() {
        let traceId = UUID()
        let spanId = UUID()
        let secret = "sk-live-secret raw thought plan tool args"
        let event = TraceEvent(
            traceId: traceId,
            spanId: spanId,
            kind: .toolError,
            level: .error,
            message: "Tool failed with \(secret)",
            metadata: [
                "thought": .string(secret),
                "plan": .string(secret),
                "arguments": .dictionary(["api_key": .string(secret)]),
                "error_message": .string(secret),
                "safe_count": .int(2)
            ],
            agentName: "ResearchAgent",
            toolName: "websearch",
            error: ErrorInfo(
                type: "FetchError",
                message: secret,
                stackTrace: ["frame with \(secret)"],
                underlyingError: secret
            )
        )

        let message = TraceEventPublicLogSanitizer.message(for: event)
        let metadata = TraceEventPublicLogSanitizer.metadata(for: event)
        let error = TraceEventPublicLogSanitizer.errorSummary(for: event.error)

        #expect(message.contains(secret) == false)
        #expect(metadata.description.contains(secret) == false)
        #expect(error.contains(secret) == false)
        #expect(metadata["safe_count"] == .int(2))
        #expect(metadata["arguments"] == .string("[redacted]"))
        #expect(metadata["thought"] == .string("[redacted]"))
        #expect(error == "FetchError: [redacted]")
    }
}
