import Foundation
import Testing

@Suite("Documentation Freshness")
struct DocumentationFreshnessTests {
    @Test("Workflow stream doc example uses current AgentEvent cases")
    func workflowStreamDocExampleUsesCurrentAgentEventCases() throws {
        let workflowSource = try readRepoFile("Sources/Swarm/Workflow/Workflow.swift")

        #expect(!workflowSource.contains("case .agentOutput"))
        #expect(workflowSource.contains("case .lifecycle(.started(input: let input))"))
        #expect(workflowSource.contains("case .lifecycle(.completed(let result))"))
        #expect(workflowSource.contains("case .lifecycle(.failed(let error))"))
    }

    @Test("API catalog header and Workflow stream line stay fresh")
    func apiCatalogHeaderAndWorkflowStreamLineStayFresh() throws {
        let catalog = try readRepoFile("docs/reference/api-catalog.md")
        let workflowSource = try readRepoFile("Sources/Swarm/Workflow/Workflow.swift")
        let workflowStreamLine = try lineNumber(containing: "public func stream(_ input", in: workflowSource)
        let scannedSourceCount = try countPublicCatalogSourceFiles()

        #expect(catalog.contains("Generated from `Sources/Swarm/` on 2026-04-30."))
        #expect(catalog.contains("- Source files scanned: \(scannedSourceCount)"))
        #expect(catalog.contains("| \(workflowStreamLine) | func | public | Workflow.stream(_:)"))
    }

    @Test("public docs do not link stale complete reference")
    func publicDocsDoNotLinkCompleteReference() throws {
        let config = try readRepoFile("docs/.vitepress/config.ts")
        let overview = try readRepoFile("docs/reference/overview.md")

        #expect(!config.contains("Complete Reference"))
        #expect(!config.contains("link: '/swarm-complete-reference'"))
        #expect(config.contains("**/swarm-complete-reference.md"))
        #expect(!overview.contains("swarm-complete-reference"))
    }

    @Test("API catalog excludes package-only and removed symbols")
    func apiCatalogExcludesPackageOnlyAndRemovedSymbols() throws {
        let catalog = try readRepoFile("docs/reference/api-catalog.md")

        #expect(!catalog.contains("AgentRuntimeIdentifiable"))
        #expect(!catalog.contains("CallableAgent"))
        #expect(!catalog.contains("Tools/ToolChainBuilder.swift"))
        #expect(!catalog.contains("| ToolChain |"))
    }

    @Test("public memory docs do not advertise removed builder APIs")
    func publicMemoryDocsDoNotAdvertiseRemovedBuilderAPIs() throws {
        let checkedFiles = [
            "README.md",
            "docs/reference/front-facing-api.md",
            "docs/reference/api-catalog.md",
            "docs/reference/docs-folder-audit-report.md",
            "docs/reference/documentation-validation-report.md",
            "docs/swarm-complete-reference.md",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(!text.contains("`MemoryOption`"), "\(file) should not mention removed MemoryOption API")
            #expect(!text.contains("`MemoryBuilder`"), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("MemoryBuilder."), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("@MemoryBuilder"), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("struct MemoryBuilder"), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("`VectorMemoryBuilder`"), "\(file) should not mention internal VectorMemoryBuilder API")
            #expect(!text.contains("`CompositeMemory`"), "\(file) should not mention removed CompositeMemory API")
            #expect(!text.contains("CompositeMemory."), "\(file) should not mention removed CompositeMemory API")
            #expect(!text.contains("actor CompositeMemory"), "\(file) should not mention removed CompositeMemory API")
        }
    }

    @Test("guardrail docs do not advertise a non-existent timeout")
    func guardrailDocsDoNotAdvertiseMissingTimeout() throws {
        let agentSource = try readRepoFile("Sources/Swarm/Agents/Agent.swift")

        #expect(!agentSource.contains("guardrails with a 30-second timeout"))
        #expect(agentSource.contains("guardrails sequentially and stops on the first failure"))
    }

    @Test("front-facing provider docs match the live base provider protocol")
    func providerDocsUsePromptBasedBaseProtocol() throws {
        let docs = try readRepoFile("docs/reference/front-facing-api.md")
        let providerSource = try readRepoFile("Sources/Swarm/Core/AgentRuntime.swift")
        let conversationSource = try readRepoFile("Sources/Swarm/Providers/ConversationInferenceProvider.swift")

        #expect(providerSource.contains("func generate(prompt: String, options: InferenceOptions) async throws -> String"))
        #expect(conversationSource.contains("public protocol ConversationInferenceProvider"))
        #expect(docs.contains("func generate(prompt: String, options: InferenceOptions) async throws -> String"))
        #expect(docs.contains("public protocol ConversationInferenceProvider: InferenceProvider"))
        #expect(!docs.contains("public protocol InferenceStreamingProvider: InferenceProvider"))
    }

    @Test("public release docs point at the latest remote tag represented by this checkout")
    func publicReleaseDocsUsePublishedVersion() throws {
        let expectedVersion = "0.5.1"
        let checkedFiles = [
            "README.md",
            "docs/index.md",
            "docs/guide/getting-started.md",
            "docs/reference/overview.md",
            "Sources/Swarm/Swarm.swift",
            "Tests/SwarmTests/V2SurfaceAuditTests.swift",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(text.contains(expectedVersion), "\(file) should mention \(expectedVersion)")
            #expect(!text.contains("0.5.2"), "\(file) should not advertise unreleased 0.5.2")
        }
    }

    @Test("CI and docs inputs required by clean clones are present")
    func cleanCloneWorkflowInputsExist() {
        let requiredPaths = [
            "package.json",
            "package-lock.json",
            ".swiftlint.yml",
            ".swiftformat",
            "Examples/CodeReviewer/Sources/CodeReviewer/main.swift",
            "scripts/ci/verify-remote-release.sh",
        ]

        for path in requiredPaths {
            let url = repoRoot.appendingPathComponent(path)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(path) should exist for clean-clone verification")
        }
    }

    private func readRepoFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func lineNumber(containing needle: String, in text: String) throws -> Int {
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(needle) {
            return index + 1
        }
        throw DocumentationFreshnessError.missingLine(needle)
    }

    private func countPublicCatalogSourceFiles() throws -> Int {
        let sources = repoRoot.appendingPathComponent("Sources/Swarm")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw DocumentationFreshnessError.missingEnumerator
        }

        var count = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let relative = url.path.replacingOccurrences(of: sources.path + "/", with: "")
            guard !relative.hasPrefix("Internal/GraphRuntime/") else { continue }
            count += 1
        }
        return count
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum DocumentationFreshnessError: Error {
    case missingEnumerator
    case missingLine(String)
}
