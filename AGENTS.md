# STADIUM2_IMPORTER Agent Contract

## Current task

Port Pokemon Stadium 2 battle FX into the Gen 1 recomp mod with native
behavioral accuracy. The runtime, router, motion, lifecycle, material, draw
packet and renderer layers exist (Luna waves 1-3). Work is now in the
integration and parity phase:

- `battle_FX_bugs.md` is the user's per-move visual test log. Original
  observations are retained; fixes are recorded as dated follow-up notes at the
  top with evidence, and a move is only called fixed after the user retests it.
- `docs/battle_fx_missing_implementation_audit.md` records the ROM-wide
  sweep and remaining diagnosed gaps. Update it when a fix changes its counts,
  and say when the sweep has not been regenerated.
- `docs/luna/research/` holds per-subsystem findings. Record new decomp or
  ROM findings there, citing function addresses and the decomp commit used.

Priorities, unless the user says otherwise: moves that draw nothing, then
missing textures/unfinished effects, then performance (lag), then polish.

## Accuracy rules

- Behavior comes from the decomp and the supported US ROM, not from guesses.
  Do not invent visual categories, substitute procedural effects, pick
  defaults, or infer semantics from move type or move name.
- If the evidence is incomplete, emit an explicit diagnostic, degrade safely,
  and report the open question. Unsupported native callbacks must never
  silently become fake geometry.
- Distinguish "matches ROM execution", "matches decomp C", and "visually
  confirmed by the user" in notes and reports. Passing tests or an absence of
  diagnostics is not visual parity.

## User-requested features

The user may ask for behavior the original game does not have (for example,
applying an effect to the whole camera, as noted for moves 45, 47 and 48).
That is allowed when the user explicitly asks for it:

- First check whether the native game already does it; if so, implement the
  native behavior instead.
- Otherwise implement it as a clearly named extension, kept separate from the
  native-parity code path, and document it as non-native in the bug log or
  research notes. Never present an extension as ROM behavior.
- Do not add features the user did not ask for.

## Source of truth

- Primary decomp: https://github.com/michiiik/pokestadiumgs (`master`). It is
  far ahead of pret for fragment 79 (battle FX, `src/fragments/79/`), and
  merged C must rebuild a matching US ROM. Region notes live in
  `docs/regions/fragments/79/` and coverage in `COVERAGE.md`.
- The fork moves quickly. Record the fork commit hash you consulted in research
  notes and handoffs. Content on unmerged fork branches is unverified.
- Functions still under `#pragma GLOBAL_ASM` must be read from the US assembly
  or checked against the supported ROM; do not reconstruct them from
  neighboring C.
- Older notes cite `pret/pokestadiumgs` commit
  `c0e10f23d90cc4f335b654711f13e53c2c07323b` (local clone:
  `/opt/git/pokestadiumgs`). Those citations remain valid; when the fork
  contradicts an older note, update the note and say which source changed.
- The supported Pokemon Stadium 2 US ROM is final authority when decomp and ROM
  execution disagree.

## Architecture

- Keep ROM decoding, runtime simulation, rendering, and battle integration as
  separate layers (see `docs/luna/README.md`).
- Preserve deterministic 30 Hz stepping. Runtime code must accept injected RNG;
  it must not consume or perturb the host game's battle RNG.
- A renderer consumes persistent runtime snapshots. It must not rebuild all
  particles from frame zero during every draw.
- Per-draw work must stay bounded; avoid copying whole snapshots or scenes per
  particle. Report performance changes with the measurement method used.

## Roles

- The root agent is the architect. It owns architecture, shared interfaces,
  public APIs, battle integration, task assignment, final review, and conflict
  resolution.
- Subagents (Luna workers or others) receive one bounded task packet and may
  edit only the paths explicitly assigned in that packet.
- Workers may inspect any relevant source, but architecture or public-contract
  changes must be returned to the architect as proposals rather than applied
  outside the worker's owned paths.

## Shared-worktree safety

- Treat every pre-existing modification and untracked file as user-owned.
- Record `git status --short` before editing and again before handoff.
- Never use `git reset`, `git checkout`, `git clean`, broad deletion, or stash
  operations. Do not commit unless the user or architect explicitly requests
  it.
- Make targeted edits and preserve unrelated changes in touched files.
- Worker path claims must not overlap. If required work crosses a claimed or
  forbidden path, stop and report the dependency to the architect.
- ROMs, cache files, `stadium2_arena_dump/`, build products, screenshots, and
  other generated artifacts are never deliverables and must not be committed.

## Validation and handoff

- Run targeted tests from the Gen1Recomp repository root
  (`/opt/git/gen1recomp`).
- Run `tools/run_battle_fx_worker_checks.sh` before handoff. Set
  `STADIUM2_REQUIRE_ROM=1` when ROM-backed acceptance is required. A skipped
  ROM audit is reported as skipped, never as passed.
- Set `LUNA_OWNED_PATHS` to the packet's space-separated owned Lua paths so the
  runner syntax-checks new, untracked deliverables. This supplements, but does
  not replace, the architect's claimed-path diff review.
- Run `git diff --check` and report any baseline failure separately from a new
  failure.
- Handoff reports must include status, files changed, commands and results,
  behavioral evidence (ROM addresses, decomp functions and commit), affected
  move IDs, limitations, and unresolved assumptions.
- The architect accepts a worker result only after reviewing its claimed diff
  and rerunning the relevant acceptance gates.

See `docs/luna/README.md` and `docs/luna/TASK_TEMPLATE.md` for the workflow.
