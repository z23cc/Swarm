import Foundation
@testable import Swarm
import Testing

@Suite("ZoniSearchTool")
struct ZoniSearchToolTests {
    @Test("Default execution returns empty search result")
    func defaultExecutionReturnsEmptySearchResult() async throws {
        var tool = ZoniSearchTool()
        tool.query = "refund window"

        let result = try await tool.execute()

        #expect(result.contains("No matching documents found"))
    }

    @Test("In-memory documents provide usable search results")
    func inMemoryDocumentsProvideUsableSearchResults() async throws {
        var tool = ZoniSearchTool(documents: [
            ZoniSearchDocument(
                id: "refunds",
                title: "Refund Policy",
                content: "Customers have 30 days to request a refund.",
                collection: "support"
            ),
            ZoniSearchDocument(
                id: "shipping",
                title: "Shipping Policy",
                content: "Ground shipping takes five days.",
                collection: "support"
            )
        ])
        tool.query = "refund"
        tool.collection = "support"

        let result = try await tool.execute()

        #expect(result.contains("Refund Policy"))
        #expect(result.contains("30 days"))
        #expect(!result.contains("Shipping Policy"))
    }
}
