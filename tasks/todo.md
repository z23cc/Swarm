# Web Security / Observability Audit Fixes

## Plan

- [x] Baseline the existing dirty web fetch changes and preserve unrelated edits.
- [x] SWARM-AUDIT-030: add focused redirect/final URL and DNS destination tests, then validate every redirect/final destination before body acceptance.
- [x] SWARM-AUDIT-031: add a focused oversized-body streaming test, then enforce `maxBodyBytes` while bytes arrive instead of after full buffering.
- [x] SWARM-AUDIT-032: add focused observability tests for thought/plan/tool/error metadata redaction, then make SwiftLog/OSLog output privacy-safe by default.
- [x] SWARM-AUDIT-038: inspect branch task/audit notes and web/security/observability code for any remaining concrete issue; if stale, document evidence and add proof where useful.
- [x] Run focused tests after each fix, then run a broader relevant test slice before pushing.
- [ ] Commit one code-changing issue per commit, push `codex/audit-web-security-20260517`, and open a PR against `codex/fix-mcp-text-content-tests` if the cluster is complete.

## Assumptions To Verify

- Existing edits in `WebSearchSupport.swift` and `WebSearchSupportTests.swift` are user-owned or prior-agent work and should be preserved unless they conflict with the requested fixes.
- The safe fetch implementation is the only web fetch path in scope for SWARM-AUDIT-030 and SWARM-AUDIT-031.
- The observability leak is limited to tracers/log sinks rather than trace event in-memory data contracts; tests should distinguish redacted exported text from structured internal event data.
- SWARM-AUDIT-038 may already be stale; evidence must come from current branch notes/code/tests, not from assumption.

## Progress

- [x] Planning complete.
- [x] SWARM-AUDIT-030 complete.
- [x] SWARM-AUDIT-031 complete.
- [x] SWARM-AUDIT-032 complete.
- [x] SWARM-AUDIT-038 complete.
- [x] Final verification complete.
- [ ] Pushed and PR created.

## Review

- SWARM-AUDIT-030: `swift test --filter WebSearchSupportTests` passes after adding DNS/redirect coverage and delegate-driven redirect/final response validation.
- SWARM-AUDIT-031: `swift test --filter WebSearchSupportTests/bodyAccumulatorRejectsOverflowBeforeAppend` first failed because `SafeWebBodyAccumulator` was missing; after adding streaming accumulation, `swift test --filter WebSearchSupportTests` passes.
- SWARM-AUDIT-032: `swift test --filter ObservabilityPrivacyTests` first failed because no public-log sanitizer existed; after adding the sanitizer and wiring SwiftLog, OSLog, ConsoleTracer, and PrettyConsoleTracer through it, `swift test --filter Observability` passes.
- SWARM-AUDIT-038: branch notes did not list a separate remaining item, but code inspection found `@Traceable` still generated raw argument, result, and error metadata. `swift test --filter TraceableMacroTests/testTraceableMacroExpansion` failed with the raw expansion, then passed after updating the macro to emit counts, argument keys, lengths, duration, and error type only. `swift test --filter TraceableMacroTests` passes.
- Final verification before push: `swift test --filter WebSearchSupportTests`, `swift test --filter Observability`, and `swift test --filter TraceableMacroTests` all pass.
