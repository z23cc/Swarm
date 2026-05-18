import Foundation

/// Checkpoint persistence configuration for advanced workflows.
public struct WorkflowCheckpointing: Sendable {
    #if SWARM_INTEGRATIONS
    let backend: any WorkflowDurableCheckpointStore

    init(backend: some WorkflowDurableCheckpointStore) {
        self.backend = backend
    }
    #else
    init() {}
    #endif

    /// In-memory checkpoint persistence.
    public static func inMemory() -> WorkflowCheckpointing {
        #if SWARM_INTEGRATIONS
        WorkflowCheckpointing(backend: WorkflowInMemoryCheckpointStore())
        #else
        WorkflowCheckpointing()
        #endif
    }

    /// File-system checkpoint persistence rooted at `directory`.
    public static func fileSystem(directory: URL) -> WorkflowCheckpointing {
        #if SWARM_INTEGRATIONS
        WorkflowCheckpointing(backend: WorkflowFileCheckpointStore(directory: directory))
        #else
        WorkflowCheckpointing()
        #endif
    }
}
