import CryptoKit
import Foundation
import MembraneCore
import Wax

actor WaxMembraneStorage: PointerStore, ContextRecallStore {
    private enum MetadataKey {
        static let kind = "membrane.kind"
        static let pointerID = "membrane.pointer.id"
        static let pointerSHA256 = "membrane.pointer.sha256"
        static let pointerDataType = "membrane.pointer.dataType"
        static let payloadEncoding = "membrane.pointer.payloadEncoding"
        static let payloadFrameID = "membrane.pointer.payloadFrameID"
        static let summary = "membrane.pointer.summary"
        static let pointerPayloadKind = "pointerPayload"
        static let pointerPayloadFrameKind = "membrane.pointer.payloadFrame"
    }

    private enum StorageFormat {
        static let payloadMarker = "\n\n__payload_base64__\n"
    }

    static var defaultStoreURL: URL {
        let fileManager = FileManager.default
        let baseURL = SwarmRuntimeEnvironment.isRunningTests
            ? fileManager.temporaryDirectory
            : (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory)
        let root = baseURL
            .appendingPathComponent("Swarm", isDirectory: true)
            .appendingPathComponent(SwarmRuntimeEnvironment.isRunningTests ? "MembraneTests" : "Membrane", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let fileName = SwarmRuntimeEnvironment.isRunningTests
            ? "membrane-store-\(UUID().uuidString).mv2s"
            : "membrane-store.mv2s"
        return root.appendingPathComponent(fileName)
    }

    private let url: URL
    private var memory: Wax.Memory?
    private var cachedPayloads: [String: Data] = [:]

    init(url: URL = defaultStoreURL) {
        self.url = url
    }

    func store(payload: Data, dataType: MemoryPointer.DataType, summary: String) async throws -> MemoryPointer {
        let pointerID = Self.pointerID(for: payload)
        let sha256 = Self.sha256Hex(payload)
        let payloadFrameID = try await persistPayloadFrame(
            payload,
            pointerID: pointerID,
            sha256: sha256,
            dataType: dataType
        )
        let storedDocument = Self.storedPointerDocument(
            pointerID: pointerID,
            summary: summary
        )

        let memory = try await ensureMemory()
        try await memory.save(
            storedDocument,
            metadata: [
                MetadataKey.kind: MetadataKey.pointerPayloadKind,
                MetadataKey.pointerID: pointerID,
                MetadataKey.pointerSHA256: sha256,
                MetadataKey.pointerDataType: dataType.rawValue,
                MetadataKey.payloadEncoding: "frame",
                MetadataKey.payloadFrameID: String(payloadFrameID),
                MetadataKey.summary: summary,
            ]
        )
        try await memory.flush()

        cachedPayloads[pointerID] = payload
        return MemoryPointer(
            id: pointerID,
            dataType: dataType,
            byteSize: payload.count,
            summary: summary
        )
    }

    func resolve(pointerID: String) async throws -> Data {
        if let cached = cachedPayloads[pointerID] {
            return cached
        }

        if let payload = try await persistedPayloadFrame(pointerID: pointerID) {
            cachedPayloads[pointerID] = payload
            return payload
        }

        let memory = try await ensureMemory()
        let results = try await memory.search(
            pointerID,
            options: .init(topK: 20, includeSurrogates: false, mode: .textOnly)
        )
        guard let item = results.items.first(where: {
            $0.metadata[MetadataKey.pointerID] == pointerID &&
                $0.metadata[MetadataKey.kind] == MetadataKey.pointerPayloadKind
        }) else {
            throw MembraneError.pointerResolutionFailed(pointerID: pointerID)
        }

        let payload = Self.decodedPayload(from: item.text) ?? Data(item.text.utf8)
        cachedPayloads[pointerID] = payload
        return payload
    }

    func delete(pointerID: String) async {
        cachedPayloads[pointerID] = nil
    }

    func recall(query: String, limit: Int) async throws -> [ContextRecallCandidate] {
        let memory = try await ensureMemory()
        let results = try await memory.search(
            query,
            options: .init(topK: max(1, limit), includeSurrogates: false, mode: .textOnly)
        )
        return results.items.map { item in
            ContextRecallCandidate(
                content: item.text,
                score: Double(item.score),
                provenance: ContextProvenance(
                    backendID: "swarm.wax",
                    recordID: String(item.frameId),
                    kind: item.metadata[MetadataKey.kind] ?? "unknown",
                    metadata: item.metadata
                )
            )
        }
    }

    private func ensureMemory() async throws -> Wax.Memory {
        if let memory {
            return memory
        }
        let resolved = try await Wax.Memory(at: url)
        memory = resolved
        return resolved
    }

    private func closeMemoryIfOpen() async throws {
        guard let existing = memory else { return }
        try await existing.close()
        memory = nil
    }

    private func openFrameStore() async throws -> Wax.FrameStore {
        if FileManager.default.fileExists(atPath: url.path) {
            return try await Wax.FrameStore.open(at: url)
        }
        return try await Wax.FrameStore.create(at: url)
    }

    private func persistPayloadFrame(
        _ payload: Data,
        pointerID: String,
        sha256: String,
        dataType: MemoryPointer.DataType
    ) async throws -> UInt64 {
        try await closeMemoryIfOpen()
        let frameStore = try await openFrameStore()
        let frameID = try await frameStore.put(
            payload,
            kind: MetadataKey.pointerPayloadFrameKind,
            metadata: [
                MetadataKey.kind: MetadataKey.pointerPayloadFrameKind,
                MetadataKey.pointerID: pointerID,
                MetadataKey.pointerSHA256: sha256,
                MetadataKey.pointerDataType: dataType.rawValue,
                MetadataKey.payloadEncoding: "raw",
            ]
        )
        await frameStore.close()
        return frameID
    }

    private func persistedPayloadFrame(pointerID: String) async throws -> Data? {
        try await closeMemoryIfOpen()
        let frameStore = try await openFrameStore()
        let frames = await frameStore.frames()
        guard let frame = frames.reversed().first(where: {
            $0.status == .active &&
                $0.metadata[MetadataKey.pointerID] == pointerID &&
                $0.metadata[MetadataKey.kind] == MetadataKey.pointerPayloadFrameKind
        }) else {
            await frameStore.close()
            return nil
        }
        let payload = try await frameStore.content(frameID: frame.id)
        await frameStore.close()
        return payload
    }

    private static func pointerID(for payload: Data) -> String {
        let hash = sha256Hex(payload)
        return "ptr_\(hash.prefix(16))"
    }

    private static func sha256Hex(_ payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private static func storedPointerDocument(
        pointerID: String,
        summary: String
    ) -> String {
        """
        pointer_id: \(pointerID)
        summary: \(summary)
        """
    }

    private static func decodedPayload(from storedText: String) -> Data? {
        if let range = storedText.range(of: StorageFormat.payloadMarker) {
            let encodedPayload = storedText[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Data(base64Encoded: String(encodedPayload))
        }
        return Data(base64Encoded: storedText)
    }
}
