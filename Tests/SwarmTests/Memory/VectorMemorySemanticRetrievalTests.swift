import Foundation
@testable import Swarm
import Testing

@Suite("VectorMemory Semantic Retrieval")
struct VectorMemorySemanticRetrievalTests {
    @Test("Search filters by threshold sorts by similarity and limits max results")
    func search_withDeterministicEmbeddings_filtersSortsAndLimitsResults() async throws {
        let provider = FixedEmbeddingProvider(embeddings: [
            "query swift": [1, 0],
            "Swift actors isolate mutable state.": [1, 0],
            "Sendable protocols cross concurrency boundaries.": [0.9, 0.4358899],
            "Structured concurrency scopes child tasks.": [0.8, 0.6],
            "Sourdough bread needs a starter.": [0, 1],
        ])
        let memory = VectorMemory(
            embeddingProvider: provider,
            similarityThreshold: 0.75,
            maxResults: 2
        )

        await memory.add(.user("Structured concurrency scopes child tasks."))
        await memory.add(.user("Sourdough bread needs a starter."))
        await memory.add(.user("Sendable protocols cross concurrency boundaries."))
        await memory.add(.user("Swift actors isolate mutable state."))

        let results = try await memory.search(query: "query swift")

        #expect(results.map(\.message.content) == [
            "Swift actors isolate mutable state.",
            "Sendable protocols cross concurrency boundaries.",
        ])
        #expect(results.count == 2)
        #expect(results[0].similarity > results[1].similarity)
        #expect(results.allSatisfy { $0.similarity >= 0.75 })
    }

    @Test("Search returns no results below threshold")
    func search_withBelowThresholdEmbeddings_returnsEmptyResults() async throws {
        let provider = FixedEmbeddingProvider(embeddings: [
            "query swift": [1, 0],
            "Sourdough bread needs a starter.": [0, 1],
        ])
        let memory = VectorMemory(
            embeddingProvider: provider,
            similarityThreshold: 0.5,
            maxResults: 10
        )

        await memory.add(.user("Sourdough bread needs a starter."))

        let results = try await memory.search(query: "query swift")

        #expect(results.isEmpty)
    }

    @Test("Diagnostics expose vector configuration and stored timestamp range")
    func diagnostics_afterMessagesAdded_reportsConfigurationAndTimestamps() async {
        let older = MemoryMessage(
            role: .user,
            content: "Older vector fact.",
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let newer = MemoryMessage(
            role: .assistant,
            content: "Newer vector fact.",
            timestamp: Date(timeIntervalSince1970: 200)
        )
        let provider = FixedEmbeddingProvider(
            modelIdentifier: "fixed-test-embeddings",
            embeddings: [
                older.content: [1, 0],
                newer.content: [0, 1],
            ]
        )
        let memory = VectorMemory(
            embeddingProvider: provider,
            similarityThreshold: 0.42,
            maxResults: 3
        )

        await memory.add(older)
        await memory.add(newer)

        let diagnostics = await memory.diagnostics()

        #expect(diagnostics.messageCount == 2)
        #expect(diagnostics.embeddingDimensions == 2)
        #expect(diagnostics.similarityThreshold == 0.42)
        #expect(diagnostics.maxResults == 3)
        #expect(diagnostics.modelIdentifier == "fixed-test-embeddings")
        #expect(diagnostics.oldestTimestamp == older.timestamp)
        #expect(diagnostics.newestTimestamp == newer.timestamp)
    }
}

private struct FixedEmbeddingProvider: EmbeddingProvider {
    let dimensions: Int
    let modelIdentifier: String
    let embeddings: [String: [Float]]

    init(
        dimensions: Int = 2,
        modelIdentifier: String = "fixed-test-embeddings",
        embeddings: [String: [Float]]
    ) {
        self.dimensions = dimensions
        self.modelIdentifier = modelIdentifier
        self.embeddings = embeddings
    }

    func embed(_ text: String) async throws -> [Float] {
        guard let embedding = embeddings[text] else {
            throw EmbeddingError.embeddingFailed(reason: "No fixed embedding for '\(text)'")
        }
        guard embedding.count == dimensions else {
            throw EmbeddingError.dimensionMismatch(expected: dimensions, got: embedding.count)
        }
        return embedding
    }
}
