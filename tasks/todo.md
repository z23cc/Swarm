# Audit Docs/Release/Linux Plan

Branch: `codex/audit-docs-release-linux-20260517`
Base: `origin/codex/fix-mcp-text-content-tests`
Scope: docs/release/example/Linux cluster only: `SWARM-AUDIT-048`, `049`, `050`, `054`, `057`, `058`.

## Assumptions To Research First

- [x] Confirm each audit ID maps to docs, release, example, or Linux/core-lane files.
- [x] Confirm existing CI/docs/example commands and avoid expanding beyond the owned cluster.
- [x] Confirm the practical local proof commands before editing.

## Implementation Checklist

- [x] `SWARM-AUDIT-048`: docs workflow builds on PRs and only deploys Pages outside PRs.
- [x] `SWARM-AUDIT-049`: remote release verification script exists, is executable, and is covered by docs freshness tests.
- [x] `SWARM-AUDIT-050`: CodeReviewer has a real executable entrypoint and standalone tests; CI/release gates run it in the core lane.
- [x] `SWARM-AUDIT-054`: release verifier fails on warning diagnostics from build/test/example logs.
- [x] `SWARM-AUDIT-057`: `SWARM_CORE_ONLY=1` removes integration dependencies and gates source references for core-only builds.
- [x] `SWARM-AUDIT-058`: Linux CI now runs the shared core verifier for `Swarm` and `SwarmMCP`.

## Verification Plan

- [x] Run targeted docs/release/example/Linux commands as practical.
- [x] Run `git diff --check`.
- [x] Push branch and open PR against `codex/fix-mcp-text-content-tests` with `gh --repo christopherkarani/Swarm`.

## Review Results

- `swift test --filter DocumentationFreshnessTests` passed.
- `npm ci` passed; npm reported four moderate audit findings in VitePress transitive dependencies.
- `npm run docs:build` passed.
- `SWARM_CORE_ONLY=1 swift test --package-path Examples/CodeReviewer` passed.
- `CONDUIT_SKIP_MLX_DEPS=1 swift build --target Swarm` passed.
- `scripts/ci/verify-linux-core.sh` passed for `Swarm` and `SwarmMCP`.

## Merge Resolution

- Resolved against the updated `codex/fix-mcp-text-content-tests` base after PRs #95-#103 merged.
- Kept the core-only dependency gate from this PR and carried forward the newer Conduit `0.3.16` pin from the merged base.
