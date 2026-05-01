import Foundation
import Swarm

let arguments = CommandLine.arguments.dropFirst()
let request = try ReviewRequest(arguments: Array(arguments))

if request.showHelp {
    printUsage()
} else {
    let input = try request.loadInput()
    let report = ReviewReport(input: input, sourceDescription: request.sourceDescription)

    StreamRenderer.printDivider("CodeReviewer")
    StreamRenderer.printLine("Input: \(report.sourceDescription)", agent: .synthesizer)
    StreamRenderer.printLine("Lines: \(report.lineCount), characters: \(report.characterCount)", agent: .performance)

    StreamRenderer.printDivider("Review Plan")
    for focus in report.focusAreas {
        StreamRenderer.printLine(focus.message, agent: focus.role)
    }

    StreamRenderer.printDivider("Swarm")
    print("Linked Swarm \(Swarm.version). Configure an inference provider to turn this deterministic CLI into a live multi-agent review.")
}

private func printUsage() {
    print(
        """
        Usage:
          swift run CodeReviewer [file]
          cat diff.patch | swift run CodeReviewer

        The CLI prints a deterministic review plan for the provided file or stdin.
        """
    )
}

struct ReviewRequest {
    let path: String?
    let showHelp: Bool

    init(arguments: [String]) throws {
        if arguments.contains("--help") || arguments.contains("-h") {
            path = nil
            showHelp = true
            return
        }

        guard arguments.count <= 1 else {
            throw CLIError.tooManyArguments
        }

        path = arguments.first
        showHelp = false
    }

    var sourceDescription: String {
        path ?? "stdin"
    }

    func loadInput() throws -> String {
        if let path {
            return try String(contentsOfFile: path, encoding: .utf8)
        }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = String(data: data, encoding: .utf8) else {
            throw CLIError.invalidUTF8
        }
        return input
    }
}

struct ReviewReport {
    struct FocusArea {
        let role: AgentRole
        let message: String
    }

    let input: String
    let sourceDescription: String

    var lineCount: Int {
        input.isEmpty ? 0 : input.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var characterCount: Int {
        input.count
    }

    var focusAreas: [FocusArea] {
        [
            FocusArea(role: .security, message: "Check trust boundaries, secret handling, unsafe file/network access, and authorization assumptions."),
            FocusArea(role: .performance, message: "Check avoidable repeated work, unbounded input growth, blocking calls, and concurrency bottlenecks."),
            FocusArea(role: .style, message: "Check API clarity, naming, test seams, and whether the smallest maintainable change was made."),
            FocusArea(role: .synthesizer, message: "Return findings first with file and line references, then summarize residual test risk.")
        ]
    }
}

enum CLIError: Error, CustomStringConvertible {
    case invalidUTF8
    case tooManyArguments

    var description: String {
        switch self {
        case .invalidUTF8:
            "Input must be valid UTF-8."
        case .tooManyArguments:
            "Pass at most one file path."
        }
    }
}
