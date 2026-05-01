/// Lightweight PromptString support used by macro tests that validate prompt
/// interpolation behavior independently from the runtime target.
struct PromptString: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, CustomStringConvertible {
    struct StringInterpolation: StringInterpolationProtocol {
        var content: String = ""
        var interpolations: [String] = []

        init(literalCapacity: Int, interpolationCount _: Int) {
            content.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            content += literal
        }

        mutating func appendInterpolation(_ value: some Any) {
            content += String(describing: value)
            interpolations.append(String(describing: type(of: value)))
        }

        mutating func appendInterpolation(_ value: String) {
            content += value
            interpolations.append("String")
        }

        mutating func appendInterpolation(_ value: [String]) {
            content += value.joined(separator: ", ")
            interpolations.append("[String]")
        }
    }

    let content: String
    let interpolations: [String]

    var description: String { content }

    init(content: String, interpolations: [String] = []) {
        self.content = content
        self.interpolations = interpolations
    }

    init(stringLiteral value: String) {
        content = value
        interpolations = []
    }

    init(stringInterpolation: StringInterpolation) {
        content = stringInterpolation.content
        interpolations = stringInterpolation.interpolations
    }
}
