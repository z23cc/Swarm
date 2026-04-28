// InferenceProviderMetadata.swift
// Swarm Framework
//
// Optional metadata for observability integrations.

import Foundation

/// Optional provider metadata used by observability integrations.
///
/// Inference providers can conform to this protocol to expose stable, non-sensitive
/// details about the backend handling LLM requests. Providers that do not conform
/// still work normally; observability integrations simply omit the unavailable
/// attributes.
public protocol InferenceProviderMetadata: Sendable {
    /// Best-known provider name, for example `openai`, `anthropic`, or `ollama`.
    var providerName: String? { get }

    /// The requested model identifier, when known.
    var modelName: String? { get }

    /// The API endpoint or base URL, when known.
    var endpointURL: URL? { get }
}

/// Immutable metadata value used by provider adapters.
public struct InferenceProviderMetadataSnapshot: InferenceProviderMetadata, Equatable {
    public let providerName: String?
    public let modelName: String?
    public let endpointURL: URL?

    public init(providerName: String? = nil, modelName: String? = nil, endpointURL: URL? = nil) {
        self.providerName = providerName
        self.modelName = modelName
        self.endpointURL = endpointURL
    }
}
