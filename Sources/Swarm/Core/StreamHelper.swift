// StreamHelper.swift
// Swarm Framework
//
// Centralized stream creation utilities with safe defaults.

import Foundation

/// Centralized stream creation utilities with safe defaults
///
/// This utility ensures all streams in Swarm use:
/// - Bounded buffers to prevent memory exhaustion
/// - Proper cancellation handling to prevent resource leaks
///
/// Usage:
/// ```swift
/// // Simple bounded stream
/// let (stream, continuation) = StreamHelper.makeStream()
///
/// // Tracked stream with automatic cancellation
/// let stream = StreamHelper.makeTrackedStream { continuation in
///     // Your async work here
///     continuation.yield(event)
///     continuation.finish()
/// }
/// ```
public enum StreamHelper {
    /// Default buffer size for all streams (prevents unbounded memory growth)
    public static let defaultBufferSize = 100

    /// Create a safe stream with bounded buffer
    ///
    /// - Parameter bufferSize: Maximum events to buffer (default: 100)
    /// - Returns: A tuple of the stream and its continuation
    ///
    /// This replaces direct `AsyncThrowingStream.makeStream()` calls which
    /// use unbounded buffers by default.
    ///
    /// - Precondition: `bufferSize` must be positive
    public static func makeStream<T: Sendable>(
        bufferSize: Int = defaultBufferSize
    ) -> (stream: AsyncThrowingStream<T, Error>,
          continuation: AsyncThrowingStream<T, Error>.Continuation) {
        precondition(bufferSize > 0, "bufferSize must be positive")
        return makeStream(bufferingPolicy: .bufferingNewest(bufferSize))
    }

    /// Create a stream with an explicit buffering policy.
    ///
    /// Use this for event streams where terminal lifecycle or tool events must
    /// not be dropped under backpressure.
    public static func makeStream<T: Sendable>(
        bufferingPolicy: AsyncThrowingStream<T, Error>.Continuation.BufferingPolicy
    ) -> (stream: AsyncThrowingStream<T, Error>,
          continuation: AsyncThrowingStream<T, Error>.Continuation) {
        return AsyncThrowingStream<T, Error>.makeStream(
            bufferingPolicy: bufferingPolicy
        )
    }

    /// Create a stream with automatic task tracking for cancellation
    ///
    /// - Important: **The operation closure MUST call `continuation.finish()` when
    ///   iteration completes successfully.** Failing to call `finish()` will cause
    ///   consumers to hang indefinitely waiting for more events. This is a common
    ///   source of deadlocks in stream-based code.
    ///
    /// - Parameters:
    ///   - bufferSize: Maximum events to buffer (default: 100)
    ///   - operation: The async operation that produces events. **MUST call `finish()`**
    /// - Returns: A stream that automatically cancels on termination
    ///
    /// This pattern ensures:
    /// - Task is cancelled when consumer stops iterating
    /// - Resources are cleaned up properly
    /// - No orphaned tasks remain
    ///
    /// - Note: Error cases are handled automatically when the closure throws,
    ///   but **normal completion requires explicit `finish()` call**.
    ///
    /// Example (correct usage):
    /// ```swift
    /// func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
    ///     StreamHelper.makeTrackedStream { continuation in
    ///         continuation.yield(.lifecycle(.started(input: input)))
    ///         let result = try await self.run(input)
    ///         continuation.yield(.lifecycle(.completed(result: result)))
    ///         continuation.finish()  // REQUIRED - don't forget!
    ///     }
    /// }
    /// ```
    ///
    /// Common mistake (will hang):
    /// ```swift
    /// // BAD: Missing finish() call
    /// StreamHelper.makeTrackedStream { continuation in
    ///     continuation.yield(.event)
    ///     // Missing continuation.finish() - consumers will hang!
    /// }
    /// ```
    public static func makeTrackedStream<T: Sendable>(
        bufferSize: Int = defaultBufferSize,
        operation: @escaping @Sendable (AsyncThrowingStream<T, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<T, Error> {
        makeTrackedStream(bufferingPolicy: .bufferingNewest(bufferSize), operation: operation)
    }

    /// Create a tracked stream with an explicit buffering policy.
    public static func makeTrackedStream<T: Sendable>(
        bufferingPolicy: AsyncThrowingStream<T, Error>.Continuation.BufferingPolicy,
        operation: @escaping @Sendable (AsyncThrowingStream<T, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<T, Error> {
        let (stream, continuation): (AsyncThrowingStream<T, Error>, AsyncThrowingStream<T, Error>.Continuation) = makeStream(bufferingPolicy: bufferingPolicy)

        let task = Task { @Sendable in
            do {
                try await operation(continuation)
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable (_: AsyncThrowingStream<T, Error>.Continuation.Termination) in
            task.cancel()
        }

        return stream
    }

    /// Create a stream with actor isolation
    ///
    /// - Important: **The operation closure MUST call `continuation.finish()` when
    ///   iteration completes successfully.** Failing to call `finish()` will cause
    ///   consumers to hang indefinitely waiting for more events.
    ///
    /// - Parameters:
    ///   - actor: The actor instance
    ///   - bufferSize: Maximum events to buffer
    ///   - operation: The async operation with actor reference. **MUST call `finish()`**
    /// - Returns: A stream that handles actor operations gracefully
    ///
    /// Use this when creating streams from actor methods.
    /// Note: Actors cannot be weakly captured in Swift.
    ///
    /// - Note: Error cases are handled automatically when the closure throws,
    ///   but **normal completion requires explicit `finish()` call**.
    public static func makeTrackedStream<A: Actor, T: Sendable>(
        for actor: A,
        bufferSize: Int = defaultBufferSize,
        operation: @escaping @Sendable (A, AsyncThrowingStream<T, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<T, Error> {
        makeTrackedStream(for: actor, bufferingPolicy: .bufferingNewest(bufferSize), operation: operation)
    }

    /// Create an actor-isolated tracked stream with an explicit buffering policy.
    public static func makeTrackedStream<A: Actor, T: Sendable>(
        for actor: A,
        bufferingPolicy: AsyncThrowingStream<T, Error>.Continuation.BufferingPolicy,
        operation: @escaping @Sendable (A, AsyncThrowingStream<T, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<T, Error> {
        let (stream, continuation): (AsyncThrowingStream<T, Error>, AsyncThrowingStream<T, Error>.Continuation) = makeStream(bufferingPolicy: bufferingPolicy)

        let task = Task { @Sendable in
            do {
                try await operation(actor, continuation)
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable (_: AsyncThrowingStream<T, Error>.Continuation.Termination) in
            task.cancel()
        }

        return stream
    }
}
