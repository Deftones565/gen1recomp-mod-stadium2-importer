# STADIUM2_IMPORTER Agent Contract

## Roles

- The root agent is the architect. It owns architecture, shared interfaces,
  public APIs, battle integration, task assignment, final review, and conflict
  resolution.
- Luna subagents are workers. Each worker receives one bounded task packet and
  may edit only the paths explicitly assigned in that packet.
- Workers may inspect any relevant source, but architecture or public-contract
  changes must be returned to the architect as proposals rather than applied
  outside the worker's owned paths.

## Shared-worktree safety

- Treat every pre-existing modification and untracked file as user-owned.
- Record `git status --short` before editing and again before handoff.
- Never use `git reset`, `git checkout`, `git clean`, broad deletion, or stash
  operations. Do not commit unless the architect explicitly requests it.
- Use `apply_patch` for source edits. Preserve unrelated changes in owned files.
- Worker path claims must not overlap. If required work crosses a claimed or
  forbidden path, stop and report the dependency to the architect.
- ROMs, cache files, `stadium2_arena_dump/`, build products, screenshots, and
  other generated artifacts are never worker deliverables and must not be
  committed.

## Battle-FX source of truth

- Use the supported Pokemon Stadium 2 US ROM and `pret/pokestadiumgs` commit
  `c0e10f23d90cc4f335b654711f13e53c2c07323b` as behavioral truth. Fragment 79
  is indexed by `src/fragments/79/fragment79_*.c`; unresolved functions must be
  checked against the corresponding US assembly or the supported ROM.
- Do not invent visual categories, substitute procedural effects, or infer
  semantics from move type or move name.
- Keep ROM decoding, runtime simulation, rendering, and battle integration as
  separate layers.
- Preserve deterministic 30 Hz stepping. Runtime code must accept injected RNG;
  it must not consume or perturb the host game's battle RNG.
- A renderer consumes persistent runtime snapshots. It must not rebuild all
  particles from frame zero during every draw.
- Unsupported native callbacks must produce explicit diagnostics and degrade
  safely; they must not silently become fake geometry.

## Worker validation and handoff

- Run the task packet's targeted tests from the Gen1Recomp repository root.
- Run `tools/run_battle_fx_worker_checks.sh` before handoff. Set
  `STADIUM2_REQUIRE_ROM=1` when ROM-backed acceptance is required.
- Set `LUNA_OWNED_PATHS` to the packet's space-separated owned Lua paths so the
  runner syntax-checks new, untracked deliverables. This supplements, but does
  not replace, the architect's claimed-path diff review.
- Run `git diff --check` and report any baseline failure separately from a new
  failure.
- Handoff reports must include status, files changed, commands and results,
  behavioral evidence, limitations, and unresolved assumptions.
- The architect accepts a worker result only after reviewing its claimed diff
  and rerunning the relevant acceptance gates.

See `docs/luna/README.md` and `docs/luna/TASK_TEMPLATE.md` for the workflow.
