import Testing
@testable import Swarm

@Suite("Memory Clear Generation")
struct MemoryClearGenerationTests {
    @Test("SummaryMemory clear wins over suspended summarization")
    func summaryMemoryClearWinsOverSuspendedSummarization() async throws {
        let summarizer = BlockingSummarizer()
        let memory = SummaryMemory(
            configuration: SummaryMemory.Configuration(
                recentMessageCount: 1,
                summarizationThreshold: 2,
                summaryTokenTarget: 100
            ),
            summarizer: summarizer,
            fallbackSummarizer: summarizer
        )
        let summarizationThreshold = await memory.configuration.summarizationThreshold

        let addTask = Task {
            for index in 1 ... summarizationThreshold {
                await memory.add(.user("message \(index)"))
            }
        }

        await summarizer.waitUntilCalled()
        await memory.clear()
        await summarizer.resume(returning: "stale summary")
        await addTask.value

        let diagnostics = await memory.diagnostics()
        #expect(await memory.isEmpty)
        #expect(diagnostics.hasSummary == false)
        #expect(diagnostics.totalMessagesProcessed == 0)
        #expect(diagnostics.summarizationCount == 0)
    }

    @Test("VectorMemory clear wins over suspended add")
    func vectorMemoryClearWinsOverSuspendedAdd() async throws {
        let embedder = BlockingEmbeddingProvider()
        let memory = VectorMemory(embeddingProvider: embedder)

        let addTask = Task {
            await memory.add(.user("stale"))
        }

        await embedder.waitUntilCalled()
        await memory.clear()
        await embedder.resumeNext(with: [1, 0, 0])
        await addTask.value

        #expect(await memory.count == 0)
        #expect(await memory.allMessages().isEmpty)
    }

    @Test("VectorMemory clear wins over suspended addAll")
    func vectorMemoryClearWinsOverSuspendedAddAll() async throws {
        let embedder = BlockingEmbeddingProvider()
        let memory = VectorMemory(embeddingProvider: embedder)

        let addTask = Task {
            await memory.addAll([.user("stale one"), .assistant("stale two")])
        }

        await embedder.waitUntilCalled()
        await memory.clear()
        await embedder.resumeNextBatch(with: [[1, 0, 0], [0, 1, 0]])
        await addTask.value

        #expect(await memory.count == 0)
        #expect(await memory.allMessages().isEmpty)
    }

    @Test("HybridMemory clear wins over suspended summarization")
    func hybridMemoryClearWinsOverSuspendedSummarization() async throws {
        let summarizer = BlockingSummarizer()
        let memory = HybridMemory(
            configuration: HybridMemory.Configuration(
                shortTermMaxMessages: 10,
                longTermSummaryTokens: 200,
                summarizationThreshold: 20
            ),
            summarizer: summarizer
        )

        let addTask = Task {
            for index in 1 ... 20 {
                await memory.add(MemoryMessage.user("message \(index)"))
            }
        }

        await summarizer.waitUntilCalled()
        await memory.clear()
        await summarizer.resume(returning: "stale hybrid summary")
        await addTask.value

        let diagnostics = await memory.diagnostics()
        #expect(await memory.isEmpty)
        #expect(diagnostics.hasSummary == false)
        #expect(diagnostics.pendingMessages == 0)
        #expect(diagnostics.totalMessagesProcessed == 0)
        #expect(diagnostics.summarizationCount == 0)
    }
}

private actor BlockingSummarizer: Summarizer {
    var isAvailable: Bool { true }

    private var continuation: CheckedContinuation<String, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func summarize(_: String, maxTokens _: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            notifyBlocked()
        }
    }

    func waitUntilCalled() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resume(returning value: String) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func notifyBlocked() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private actor BlockingEmbeddingProvider: EmbeddingProvider {
    let dimensions = 3
    let modelIdentifier = "blocking"

    private var singleContinuations: [CheckedContinuation<[Float], Error>] = []
    private var batchContinuations: [CheckedContinuation<[[Float]], Error>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func embed(_: String) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            singleContinuations.append(continuation)
            notifyCalled()
        }
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        return try await withCheckedThrowingContinuation { continuation in
            batchContinuations.append(continuation)
            notifyCalled()
        }
    }

    func waitUntilCalled() async {
        if !singleContinuations.isEmpty || !batchContinuations.isEmpty {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resumeNext(with embedding: [Float]) {
        singleContinuations.removeFirst().resume(returning: embedding)
    }

    func resumeNextBatch(with embeddings: [[Float]]) {
        batchContinuations.removeFirst().resume(returning: embeddings)
    }

    private func notifyCalled() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
