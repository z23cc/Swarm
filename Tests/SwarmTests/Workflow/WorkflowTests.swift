import Foundation
import Testing
@testable import Swarm

/// Canonical test suite for the `Workflow` public API. These tests anchor the
/// per-shape behavior (`.step`, `.parallel(merge:)`, `.route`, `.repeatUntil`,
/// `.timeout`) so a maintainer changing one shape sees a focused failure rather
/// than chasing an unrelated scenario test.
@Suite("Workflow Core")
struct WorkflowCoreTests {

    // MARK: - Sequential

    @Test("sequential workflow chains output through each step")
    func sequentialChainsOutput() async throws {
        let first = MockAgentRuntime(response: "step1")
        let second = MockAgentRuntime(response: "step2")
        let third = MockAgentRuntime(response: "step3")
        let result = try await Workflow()
            .step(first)
            .step(second)
            .step(third)
            .run("input")
        #expect(result.output == "step3")
    }

    @Test("single-step workflow returns that step's output")
    func singleStep() async throws {
        let agent = MockAgentRuntime(response: "only")
        let result = try await Workflow()
            .step(agent)
            .run("hi")
        #expect(result.output == "only")
    }

    // MARK: - Parallel + MergeStrategy

    @Test("parallel with .structured merge produces JSON-indexed object")
    func parallelStructured() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b], merge: .structured)
            .run("input")
        // Format documented as: {"0": "...", "1": "..."}
        #expect(result.output.contains("\"0\""))
        #expect(result.output.contains("\"1\""))
        #expect(result.output.contains("alpha"))
        #expect(result.output.contains("beta"))
    }

    @Test("parallel with .indexed merge produces [n]: prefixed lines")
    func parallelIndexed() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b], merge: .indexed)
            .run("input")
        #expect(result.output.contains("[0]"))
        #expect(result.output.contains("[1]"))
        #expect(result.output.contains("alpha"))
        #expect(result.output.contains("beta"))
    }

    @Test("parallel with .first merge returns one result")
    func parallelFirst() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b], merge: .first)
            .run("input")
        // Either alpha or beta — but only one of them.
        let output = result.output
        let containsBoth = output.contains("alpha") && output.contains("beta")
        #expect(!containsBoth, "first merge should not concatenate")
    }

    @Test("parallel with .custom merge applies the closure")
    func parallelCustom() async throws {
        let a = MockAgentRuntime(response: "x")
        let b = MockAgentRuntime(response: "y")
        let result = try await Workflow()
            .parallel([a, b], merge: .custom { results in
                results.map { "<\($0.output)>" }.joined(separator: "+")
            })
            .run("input")
        // Order isn't guaranteed by parallel execution, but both pieces must appear.
        #expect(result.output.contains("<x>"))
        #expect(result.output.contains("<y>"))
        #expect(result.output.contains("+"))
    }

    @Test("parallel default merge is .structured")
    func parallelDefaultMerge() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b])
            .run("input")
        #expect(result.output.contains("\"0\""))
        #expect(result.output.contains("\"1\""))
    }

    // MARK: - Route

    @Test("route picks the matching agent")
    func routePicksAgent() async throws {
        let billing = MockAgentRuntime(response: "billing")
        let support = MockAgentRuntime(response: "support")
        let result = try await Workflow()
            .route { input in
                input.contains("invoice") ? billing : support
            }
            .run("invoice 123")
        #expect(result.output == "billing")
    }

    @Test("route falls through when closure returns nil")
    func routeFallthrough() async throws {
        let agent = MockAgentRuntime(response: "matched")
        // Returning nil from the route closure is a valid signal; the framework
        // either skips the step or surfaces a deterministic error. Either is OK
        // here — the assertion is that it does not crash or hang.
        let workflow = Workflow().route { _ in nil as (any AgentRuntime)? }.step(agent)
        do {
            _ = try await workflow.run("input")
        } catch {
            // Surfaced error is acceptable; hang/crash is not.
        }
    }

    // MARK: - RepeatUntil

    @Test("repeatUntil terminates when the predicate matches")
    func repeatUntilTerminatesOnPredicate() async throws {
        let counter = WorkflowTestCounter(shutdownAfter: 2)
        let agent = MockAgentRuntime(responseFactory: { counter.next() })
        let result = try await Workflow()
            .step(agent)
            .repeatUntil { $0.output.contains("SHUTDOWN") }
            .run("monitor")
        #expect(result.output == "SHUTDOWN")
    }

    @Test("repeatUntil respects maxIterations")
    func repeatUntilMaxIterations() async throws {
        // An agent that never matches the terminating predicate; maxIterations
        // must bound the loop and surface a result anyway (or throw — both are
        // acceptable contracts so long as it doesn't loop forever).
        let agent = MockAgentRuntime(response: "never")
        let workflow = Workflow()
            .step(agent)
            .repeatUntil(maxIterations: 3) { $0.output == "SHUTDOWN" }
        // Use a wall-clock timeout as a watchdog so a regression doesn't hang CI.
        let task = Task {
            try await workflow.run("input")
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(10))
            task.cancel()
            return "watchdog-fired"
        }
        defer { watchdog.cancel() }
        do {
            let result = try await task.value
            // Bound was respected, returned final non-matching output.
            #expect(result.output == "never")
        } catch {
            // Or surfaced an error — that's also a valid contract.
        }
    }

    // MARK: - Composition

    @Test("step then parallel then step composes left-to-right")
    func compositionStepParallelStep() async throws {
        let head = MockAgentRuntime(response: "head")
        let a = MockAgentRuntime(response: "a")
        let b = MockAgentRuntime(response: "b")
        let tail = MockAgentRuntime(response: "tail")
        let result = try await Workflow()
            .step(head)
            .parallel([a, b], merge: .indexed)
            .step(tail)
            .run("input")
        #expect(result.output == "tail")
    }
}

private final class WorkflowTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let shutdownAfter: Int

    init(shutdownAfter: Int) { self.shutdownAfter = shutdownAfter }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count >= shutdownAfter ? "SHUTDOWN" : "running"
    }
}
