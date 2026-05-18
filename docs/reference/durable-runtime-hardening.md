# Durable Runtime Non-Fork Hardening Contract

> **Internal note:** This document describes package-internal durable graph runtime contracts. It is not public API documentation and is excluded from the public website build.

This document defines the internal runtime hardening surface for Swarm's durable graph runtime without native fork support.

## Event Schema Version

- Internal run events carry a dedicated schema-version metadata key.
- The runtime controller stamps emitted events with the current schema version when it is absent.

## Run Control APIs

### Validation

Validation is performed by the internal graph runtime before dispatching a run.

Throws typed runtime errors:

- model client missing
- tool registry missing
- checkpoint store missing
- invalid run options

### External Writes

The internal `ExternalWriteRequest` value carries a Hive thread ID, channel writes, and run options. Runtime code applies it through the internal run-control path.

Validation and failure semantics:

- unknown channel
- task-local scope write attempt
- value type mismatch
- single-value update-policy violation
- pending interrupt state

Commit semantics are all-or-nothing: no runtime state publish occurs when validation fails.

### Resume Contract Prevalidation

`resume(_:)` now performs typed prevalidation before dispatch:

- no checkpoint store
- no checkpoint
- no pending interrupt
- interrupt ID mismatch
- unsupported checkpoint format tag

## Checkpoint Capability Contract

```swift
enum HiveCheckpointQueryCapability: Sendable, Equatable {
    case unavailable
    case latestOnly
    case queryable
}

// Internal run-control helpers expose latest-checkpoint and history queries
// where the configured checkpoint store supports them.
```

Unsupported query operations remain explicitly typed:

- unsupported query operation

## Typed Runtime State Snapshot

```swift
public struct RuntimeStateSnapshot: Sendable, Equatable {
    public let threadID: InternalThreadID
    public let runID: InternalRunID?
    public let stepIndex: Int?
    public let interruption: RuntimeInterruptionSummary?
    public let checkpointID: CheckpointID?
    public let frontier: RuntimeFrontierSummary
    public let channelState: RuntimeChannelStateSummary?
    public let eventSchemaVersion: String
    public let source: RuntimeStateSnapshotSource
}

public func getState(
    threadID: InternalThreadID
) async throws -> RuntimeStateSnapshot?
```

Missing thread behavior:

- Returns `nil` when no checkpoint, no in-memory store, and no tracked attempt state exists for `threadID`.

## Determinism + Replay Utilities

```swift
public enum RuntimeDeterminism {
    public static func projectTranscript(
        _ events: [RuntimeEvent],
        expectedSchemaVersion: String
    ) throws -> CanonicalTranscript

    public static func transcriptHash(
        _ events: [RuntimeEvent],
        expectedSchemaVersion: String
    ) throws -> String

    public static func finalStateHash(
        _ snapshot: RuntimeStateSnapshot,
        includeRuntimeIdentity: Bool = false
    ) throws -> String

    public static func firstTranscriptDiff(
        expected: CanonicalTranscript,
        actual: CanonicalTranscript
    ) -> RuntimeDeterminismDiff?

    public static func firstStateDiff(
        expected: RuntimeStateSnapshot,
        actual: RuntimeStateSnapshot,
        includeRuntimeIdentity: Bool = false
    ) -> RuntimeDeterminismDiff?
}
```

Replay compatibility checks are typed:

```swift
public enum TranscriptCompatibilityError: Error, Sendable, Equatable {
    case missingSchemaVersion(eventIndex: Int)
    case incompatibleSchemaVersion(expected: String, found: String, eventIndex: Int)
}
```

## Cancel + Checkpoint Race Classification

```swift
public enum CancelCheckpointResolution: Sendable, Equatable {
    case notCancelled
    case cancelledWithoutCheckpoint(latestCheckpointID: CheckpointID?)
    case cancelledAfterCheckpointSaved(checkpointID: CheckpointID)
}

public static func classifyCancelCheckpointRace(
    events: [RuntimeEvent],
    outcome: RuntimeOutcome
) -> CancelCheckpointResolution
```

This provides deterministic post-run classification when cancellation overlaps checkpoint persistence.
