import Swarm
import Testing

private struct PublicCompileTool: Tool {
    struct Input: Codable, Sendable {}

    let name = "public_compile_tool"
    let description = "Compile-only public API tool"
    let parameters: [ToolParameter] = []

    func execute(_: Input) async throws -> String {
        "ok"
    }
}

@Suite("README Provider Compile Tests")
struct ReadmeProviderCompileTests {
    @Test("README-style provider factories compile through public import")
    func readmeProviderFactoriesCompile() throws {
        _ = try Agent("Use Anthropic.", inferenceProvider: .anthropic(key: "test-key")) {
            PublicCompileTool()
        }

        _ = try Agent("Use OpenAI.", provider: .openAI(key: "test-key")) {
            PublicCompileTool()
        }

        let ollamaAgent = try Agent("Use local models.")
        let _: any AgentRuntime = ollamaAgent.environment(\.inferenceProvider, .ollama(model: "mistral"))

        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
            _ = try Agent("Use Foundation Models.", inferenceProvider: .foundationModels())
        }
    }

    @Test("README dynamic tool examples compile through public import")
    func readmeDynamicToolExamplesCompile() throws {
        _ = try Agent("Use closure tools.") {
            FunctionTool(name: "reverse", description: "Reverses text") { args in
                let text = try args.require("text", as: String.self)
                return .string(String(text.reversed()))
            }

            #if canImport(Darwin)
                CalculatorTool()
            #endif
        }
    }
}
