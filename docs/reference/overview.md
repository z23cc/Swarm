# API Reference

The complete API reference covers every public type, protocol, and API in the Swarm framework.

## Complete Reference

The **[Complete API Reference](/swarm-complete-reference)** is an archival deep reference. For current 0.5.0 usage, prefer the guide pages and API catalog first.

1. **Overview & Architecture** — What Swarm is, layer diagram, platform requirements
2. **Quick Start** — Minimal working example
3. **Agents** — All agent types, `AgentRuntime` protocol, configuration
4. **Tools** — `@Tool` macro, `FunctionTool`, tool chaining, parallel execution
5. **Workflow** — Fluent core API (`step`, `parallel`, `route`, `repeatUntil`, `timeout`) plus durable checkpoint/resume APIs under `workflow.durable`
6. **Handoffs** — `HandoffConfiguration` and handoff coordination
8. **Memory** — All memory types, sessions, backends, embeddings
9. **Guardrails** — Input/output/tool guardrails, tripwire modes
10. **Resilience** — Retry, circuit breaker, fallback, timeout
11. **Observability** — Tracers, trace events, spans, metrics
12. **MCP Integration** — Client and server
13. **Providers** — LLM providers, MultiProvider, Foundation Models
14. **Macros** — `@Tool`, `@Parameter`, `@AgentActor`, `@Traceable`, `#Prompt`, `@Builder`
15. **Durable Runtime** — DAG compilation, checkpointing, resume through Swarm-owned APIs

## By Topic

| Topic | Description |
|---|---|
| [Agents](/agents) | Agent types, configuration, `@AgentActor` macro |
| [Tools](/tools) | `@Tool` macro, `FunctionTool`, runtime toggling |
| [Workflow](/guide/getting-started) | Fluent workflow composition and execution |
| [Handoffs](/Handoffs) | Agent handoffs and routing between runtime agents |
| [Memory](/memory) | Conversation, Vector, Summary, SwiftData backends |
| [Streaming](/streaming) | `AgentEvent` streaming, SwiftUI integration |
| [Guardrails](/guardrails) | Input/output validation, tripwires |
| [Resilience](/resilience) | Retry, circuit breakers, fallback, timeouts |
| [Observability](/guide/opentelemetry-tracing) | Tracing, OpenTelemetry, `OSLogTracer`, `SwiftLogTracer`, metrics |
| [MCP](/mcp) | Model Context Protocol client and server |
| [Providers](/providers) | Inference providers, `MultiProvider` routing |
| [Durable Runtime Hardening](/durable-runtime-hardening) | Internal implementation note covering run control, checkpoint capability, and deterministic transcript/state hashing |
