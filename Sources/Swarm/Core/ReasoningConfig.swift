// ReasoningConfig.swift
// Swarm Framework
//
// Swarm-level mirror of Conduit's ReasoningConfig. Lives at the Swarm boundary
// so consumers don't need to depend on Conduit types directly. Translated to
// Conduit's ReasoningConfig at the ConduitInferenceProvider boundary.

import Foundation

/// Reasoning effort level for models that support extended thinking / chain-of-
/// thought reasoning (e.g. OpenAI o-series, OpenRouter `:thinking` variants).
///
/// Maps directly to Conduit's `ReasoningEffort`. Anthropic uses a separate
/// `ThinkingConfig` mechanism not covered by this enum.
public enum ReasoningEffort: String, Sendable, Hashable, Codable, CaseIterable {
    /// Maximum reasoning time.
    case xhigh
    /// Extensive reasoning.
    case high
    /// Balanced reasoning.
    case medium
    /// Light reasoning.
    case low
    /// Very brief reasoning.
    case minimal
    /// No reasoning — standard generation. Use this to explicitly
    /// disable reasoning when the base/provider config has it enabled;
    /// `nil` means "preserve base config", which can't override an
    /// inherited reasoning setting. Mirrors Conduit's `ReasoningEffort.none`,
    /// which serializes as `effort: "none"` on the wire.
    case none
}

/// Configuration for extended thinking / reasoning mode.
///
/// Use `effort` for providers that accept a qualitative level (OpenAI o1,
/// OpenRouter `:thinking`). Use `maxTokens` to allocate a token budget
/// directly. Use `enabled` for simple on/off providers (e.g. some o1 endpoints).
/// Use `exclude` to suppress reasoning details from the response payload.
///
/// Mirrors Conduit's `ReasoningConfig` (Vendor/Conduit/Sources/Conduit/Core/Types/GenerateConfig.swift)
/// so Swarm consumers don't import Conduit directly.
public struct ReasoningConfig: Sendable, Hashable, Codable {
    /// Reasoning effort level (qualitative).
    public var effort: ReasoningEffort?

    /// Maximum tokens for reasoning. Alternative to `effort`.
    public var maxTokens: Int?

    /// Whether to exclude reasoning details from the response.
    public var exclude: Bool?

    /// Whether reasoning is enabled. Used by simple-flag providers.
    public var enabled: Bool?

    public init(
        effort: ReasoningEffort? = nil,
        maxTokens: Int? = nil,
        exclude: Bool? = nil,
        enabled: Bool? = nil
    ) {
        self.effort = effort
        self.maxTokens = maxTokens
        self.exclude = exclude
        self.enabled = enabled
    }
}
