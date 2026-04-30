import Foundation
@testable import Swarm
import Testing

@Suite("SemanticCompactorTool Behavior")
struct SemanticCompactorToolBehaviorTests {
    @Test("Empty input returns message without calling summarizer")
    func execute_withEmptyInput_returnsNoTextMessage() async throws {
        let summarizer = MockSummarizer.succeeding(with: "should not be used")
        var tool = SemanticCompactorTool(summarizer: summarizer)
        tool.text = " \n\t "

        let result = try await tool.execute()

        #expect(result == "No text provided to compact.")
        #expect(await summarizer.callCount == 0)
    }

    @Test("Summary strategy passes original text and converts max length to tokens")
    func execute_withSummaryStrategy_passesOriginalTextAndMaxTokens() async throws {
        let summarizer = MockSummarizer.succeeding(with: "short summary")
        var tool = SemanticCompactorTool(summarizer: summarizer)
        tool.text = "Swift actors isolate mutable state."
        tool.strategy = "summary"
        tool.maxLength = 80

        let result = try await tool.execute()

        #expect(result == "short summary")
        let call = try #require(await summarizer.lastCall)
        #expect(call.text == "Swift actors isolate mutable state.")
        #expect(call.maxTokens == 20)
    }

    @Test("Key points strategy wraps text in bullet extraction prompt")
    func execute_withKeyPointsStrategy_usesKeyPointPrompt() async throws {
        let summarizer = MockSummarizer.succeeding(with: "- point")
        var tool = SemanticCompactorTool(summarizer: summarizer)
        tool.text = "Swarm has tools, memory, and orchestration."
        tool.strategy = "bullets"
        tool.maxLength = 120

        _ = try await tool.execute()

        let call = try #require(await summarizer.lastCall)
        #expect(call.text.contains("Extract the key points"))
        #expect(call.text.contains("Key Points:"))
        #expect(call.text.contains(tool.text))
        #expect(call.maxTokens == 30)
    }

    @Test("Semantic core strategy wraps text in minimal compaction prompt")
    func execute_withSemanticCoreStrategy_usesSemanticCorePrompt() async throws {
        let summarizer = MockSummarizer.succeeding(with: "core facts")
        var tool = SemanticCompactorTool(summarizer: summarizer)
        tool.text = "Release notes mention names, dates, figures, and critical facts."
        tool.strategy = "compact"
        tool.maxLength = 64

        _ = try await tool.execute()

        let call = try #require(await summarizer.lastCall)
        #expect(call.text.contains("absolute semantic core"))
        #expect(call.text.contains("Core Info:"))
        #expect(call.text.contains(tool.text))
        #expect(call.maxTokens == 16)
    }

    @Test("Summarizer failure falls back to deterministic truncation")
    func execute_withFailingSummarizer_returnsTruncatedFallback() async throws {
        let summarizer = MockSummarizer.failing(with: SummarizerError.timeout)
        let text = String(repeating: "First sentence. Second sentence. ", count: 12)
        var tool = SemanticCompactorTool(summarizer: summarizer)
        tool.text = text
        tool.strategy = "summary"
        tool.maxLength = 40

        let result = try await tool.execute()

        #expect(await summarizer.callCount == 1)
        #expect(result.count < text.count)
        #expect(result.contains("First sentence"))
    }
}
