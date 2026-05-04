import Foundation
import Testing
@testable import Swarm

@Suite("Agent.toolOutputText")
struct AgentToolOutputTextTests {
    @Test("Plain string passes through unchanged")
    func stringPassthrough() {
        #expect(Agent.toolOutputText(for: .string("hello")) == "hello")
        #expect(Agent.toolOutputText(for: .string("")) == "")
    }

    @Test("Plain string preserves embedded quotes and newlines verbatim")
    func stringPreservesSpecialCharsLiteral() {
        let raw = "quoted \"value\" with newline\nsecond line"
        #expect(Agent.toolOutputText(for: .string(raw)) == raw)
    }

    @Test("Dictionary serializes as JSON with sorted keys and escaped strings")
    func dictionaryProducesValidJSON() throws {
        let value = SendableValue.dictionary([
            "message": .string("quoted \"value\" with newline\nsecond line"),
            "count": .int(42),
            "items": .array([.string("a"), .string("b")])
        ])

        let text = Agent.toolOutputText(for: value)

        // sorted keys: count, items, message
        #expect(text.hasPrefix("{\"count\":42,\"items\":"))

        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let dictionary = try #require(object)
        #expect(dictionary["message"] as? String == "quoted \"value\" with newline\nsecond line")
        #expect(dictionary["count"] as? Int == 42)
        #expect(dictionary["items"] as? [String] == ["a", "b"])
    }

    @Test("Nested dictionaries and arrays round-trip through JSON")
    func nestedRoundTrip() throws {
        let value = SendableValue.dictionary([
            "outer": .dictionary([
                "inner": .array([.int(1), .int(2), .int(3)]),
                "flag": .bool(true)
            ])
        ])

        let text = Agent.toolOutputText(for: value)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let dictionary = try #require(object)
        let outer = try #require(dictionary["outer"] as? [String: Any])
        #expect(outer["inner"] as? [Int] == [1, 2, 3])
        #expect(outer["flag"] as? Bool == true)
    }

    @Test("Scalar non-string values serialize as JSON fragments")
    func scalarFragments() {
        #expect(Agent.toolOutputText(for: .int(42)) == "42")
        #expect(Agent.toolOutputText(for: .double(3.5)) == "3.5")
        #expect(Agent.toolOutputText(for: .bool(true)) == "true")
        #expect(Agent.toolOutputText(for: .bool(false)) == "false")
        #expect(Agent.toolOutputText(for: .null) == "null")
    }

    @Test("Top-level array serializes as JSON array")
    func topLevelArray() throws {
        let value = SendableValue.array([
            .string("a\"b"),
            .int(1),
            .null
        ])

        let text = Agent.toolOutputText(for: value)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any]
        let array = try #require(object)
        #expect(array.count == 3)
        #expect(array[0] as? String == "a\"b")
        #expect(array[1] as? Int == 1)
        #expect(array[2] is NSNull)
    }

    @Test("Non-finite double falls back to description without crashing")
    func nonFiniteDoubleFallsBack() {
        // JSONSerialization raises NSException (not a Swift error) on NaN/Infinity.
        // The helper must screen the value before serializing — falling back to
        // description preserves prior behavior on this edge case without crashing.
        #expect(Agent.toolOutputText(for: .double(.nan)) == SendableValue.double(.nan).description)
        #expect(Agent.toolOutputText(for: .double(.infinity)) == SendableValue.double(.infinity).description)
        #expect(Agent.toolOutputText(for: .double(-.infinity)) == SendableValue.double(-.infinity).description)
    }

    @Test("Non-finite double nested inside dictionary falls back without crashing")
    func nonFiniteNestedFallsBack() {
        let value = SendableValue.dictionary([
            "ok": .int(1),
            "broken": .array([.double(.nan)])
        ])
        let text = Agent.toolOutputText(for: value)
        // Falls back to description — must not be valid JSON and must not crash.
        #expect(!text.isEmpty)
    }
}
