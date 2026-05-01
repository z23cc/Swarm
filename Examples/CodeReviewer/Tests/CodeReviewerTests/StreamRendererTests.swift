import Foundation
import Testing
@testable import CodeReviewer

@Suite("StreamRenderer")
struct StreamRendererTests {

    @Test("formats security prefix with red color")
    func securityPrefix() {
        let result = StreamRenderer.format("hello", agent: .security)
        #expect(result.contains("[Security]"))
        #expect(result.contains("hello"))
        #expect(result.contains(StreamRenderer.ANSICode.red))
    }

    @Test("formats performance prefix with yellow color")
    func performancePrefix() {
        let result = StreamRenderer.format("world", agent: .performance)
        #expect(result.contains("[Performance]"))
        #expect(result.contains(StreamRenderer.ANSICode.yellow))
    }

    @Test("formats style prefix with blue color")
    func stylePrefix() {
        let result = StreamRenderer.format("test", agent: .style)
        #expect(result.contains("[Style]"))
        #expect(result.contains(StreamRenderer.ANSICode.blue))
    }

    @Test("formats synthesizer prefix with green color")
    func synthesizerPrefix() {
        let result = StreamRenderer.format("summary", agent: .synthesizer)
        #expect(result.contains("[Summary]"))
        #expect(result.contains(StreamRenderer.ANSICode.green))
    }
}

@Suite("ReviewRequest")
struct ReviewRequestTests {
    @Test("parses help flag")
    func helpFlag() throws {
        let request = try ReviewRequest(arguments: ["--help"])
        #expect(request.showHelp)
        #expect(request.path == nil)
    }

    @Test("rejects too many arguments")
    func tooManyArguments() {
        #expect(throws: CLIError.tooManyArguments) {
            _ = try ReviewRequest(arguments: ["one.swift", "two.swift"])
        }
    }

    @Test("loads file input")
    func loadsFileInput() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try "let value = 1\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let request = try ReviewRequest(arguments: [url.path])

        #expect(request.sourceDescription == url.path)
        #expect(try request.loadInput() == "let value = 1\n")
    }
}

@Suite("ReviewReport")
struct ReviewReportTests {
    @Test("counts lines and characters")
    func countsLinesAndCharacters() {
        let report = ReviewReport(input: "one\ntwo\n", sourceDescription: "stdin")

        #expect(report.lineCount == 3)
        #expect(report.characterCount == 8)
        #expect(report.focusAreas.count == 4)
    }
}
