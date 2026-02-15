# HCNews Orchestrator Refactor Spec v1 (Draft)

## Purpose

Refactor orchestration to reduce duplication, remove hidden coupling, and make behavior easier to test and evolve, while preserving output format and CLI behavior.

## Non-goals

- Rewrite all components in another language.
- Change public output format/order by default.
- Replace cache format/paths in one step.
- Remove legacy orchestration before parity is verified.

## Invariants

- `hcnews.sh` output shape remains stable by default.
- Existing cache flags (`--no-cache`, `--force`) stay compatible.
- Optional component failures do not break full output.
- Rollback to legacy path must be possible by feature flag.

## Proposed architecture

### Modules

- `scripts/lib/components.sh`
  - Declarative component registry.
- `scripts/lib/orchestrator.sh`
  - Plan, run, collect, status, render helpers.
- `scripts/lib/jobs.sh`
  - Runtime adapter for background jobs (function + args, no eval strings).
- `scripts/lib/common.sh`
  - Cache/TTL helpers remain source of truth.
- Entrypoints (`hcnews.sh`, `refresh_cache.sh`, `build_daily.sh`)
  - Thin profile orchestration + rendering only.

### Profiles

- `main`: interactive/output generation (`hcnews.sh`).
- `refresh`: background cache refresh (`refresh_cache.sh`).
- `daily_build`: static generation (`build_daily.sh`).

## Registry schema (starter)

Each component row in registry should define:

- `name`
- `producer_fn`
- `cache_key`
- `ttl_key`
- `profiles` (`main`, `refresh`, `daily_build`)
- `enabled_default` (`true|false`)
- `required` (`true|false`)
- `parallel_group` (`network|local|serial`)
- `timeout_sec`
- `retries`
- `render_order` (for main profile)

## Starter component table (current state)

| name | producer_fn | currently rendered (main) | currently scheduled (main) | profile notes |
|---|---|---:|---:|---|
| header | `hc_component_header` | yes | yes | local |
| moonphase | `hc_component_moonphase` | yes | yes | network |
| holidays | `hc_component_holidays` | yes | yes | local |
| states | `hc_component_states` | yes | yes | local |
| weather | `hc_component_weather` | yes | yes | network |
| rss | `hc_component_rss` | yes | yes | network |
| exchange | `hc_component_exchange` | yes | yes | network |
| sports | `hc_component_sports` | yes | yes | network |
| onthisday | `hc_component_onthisday` | yes | yes | network |
| didyouknow | `hc_component_didyouknow` | yes | yes | network |
| bicho | `hc_component_bicho` | yes | yes | network |
| saints | `hc_component_saints` | yes | yes | network |
| emoji | `hc_component_emoji` | yes | yes | local |
| musicchart | `hc_component_musicchart` | no | no (disabled) | optional |
| earthquake | `hc_component_earthquake` | no | no (disabled) | optional |
| quote | `hc_component_quote` | no | no (disabled) | optional |
| futuro | `hc_component_futuro` | no | no (disabled) | optional |

## Orchestrator contracts

### Planner

- `hc_orch_plan <profile> <plan_ref>`
  - Reads registry.
  - Applies feature flags and profile filter.
  - Produces ordered execution plan.

### Runner

- `hc_orch_run <plan_ref> <result_ref>`
  - Executes `local` serially.
  - Executes `network` with bounded concurrency.
  - Applies timeout/retry policies.
  - Captures output/status/elapsed for each component.

### Collector/renderer

- `hc_orch_render_main <result_ref>`
  - Renders only enabled components in stable order.
  - Does not trigger fetch work.

### Status

- `hc_orch_status <result_ref>`
  - Per-component status summary: `ok|cache_hit|timeout|error|skipped`.

## Result map contract

Result map keys (associative):

- `result["<name>.status"]`
- `result["<name>.output"]`
- `result["<name>.elapsed_ms"]`
- `result["<name>.source"]` (`cache|fresh|fallback`)

## Error policy

- Required component failure:
  - `main`: fallback text, continue.
  - `refresh`: record failure, continue other components.
- Optional component failure:
  - mark status `error`, omit block or print lightweight fallback.
- Timeouts:
  - mark `timeout`; no hard exit unless strict mode enabled.

## Concurrency policy

- Global max workers via `HCNEWS_ORCH_MAX_PARALLEL`.
- Default target: conservative value (for example `4`).
- No unbounded fan-out in refresh profile.

## Cache policy ownership

- Cache key/path resolution must go through common helpers.
- TTL source of truth must be `HCNEWS_CACHE_TTL`.
- Entrypoints should not hardcode cache file names.

## Feature flags

- `HCNEWS_ORCH_V2=false` (initial default)
- `HCNEWS_ORCH_PARITY_CHECK=false`
- `HCNEWS_ORCH_MAX_PARALLEL=4`
- `HCNEWS_ORCH_STRICT_MODE=false`

## Phased migration plan

1. **Stabilize P0 behavior**
   - Patch known correctness drifts.
   - Add smoke checks for help + cache flags.
2. **Introduce registry (no behavior change)**
   - Add metadata only; legacy path still active.
3. **Add orchestrator v2 behind feature flag**
   - Implement planner/runner/status with no rendering change.
4. **Migrate low-risk components first**
   - `moonphase`, `exchange`, `didyouknow`.
5. **Add parity mode**
   - Compare legacy/v2 per-component output hashes in CI/local script.
6. **Migrate core components**
   - `weather`, `rss`, `saints`, `sports`, `onthisday`, `bicho`.
7. **Adopt v2 in refresh/build profiles**
   - Remove duplicate orchestration logic from those scripts.
8. **Default switch + cleanup**
   - Set `HCNEWS_ORCH_V2=true` by default.
   - Keep rollback path for one release cycle.

## Test plan

### Unit-level (shell tests)

- Registry validation.
- Planner profile filtering.
- Timeout/retry behavior.
- Status/result map integrity.

### Integration-level

- `bash hcnews.sh --help`
- `bash hcnews.sh`
- `bash hcnews.sh --force`
- `bash refresh_cache.sh help`
- `bash build_daily.sh` smoke

### Parity checks

- Compare legacy and v2 rendered block content for enabled components.
- Allow only known accepted diffs.

### Failure tests

- Simulated API timeout per network component.
- Partial provider outage with graceful output.

## Rollback strategy

- Immediate rollback by setting `HCNEWS_ORCH_V2=false`.
- Keep legacy orchestration path until parity has passed for a full cycle.
- Keep old renderer available while v2 runner is stabilized.

## Acceptance criteria

- Output parity for main profile (except explicitly approved changes).
- No regression in help/cache flags.
- Lint remains clean.
- Measurable reduction in orchestration duplication and complexity.
- Forced-run reliability improved under slow APIs via timeout/retry controls.

## Open questions

- Which optional components should remain disabled by default long-term?
- Exact timeout/retry defaults per provider?
- Should registry be pure Bash arrays or a data file parsed at runtime?
- Is strict mode desired for CI only or also for production runs?
