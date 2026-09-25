# LUNA-XXX: Task title

## Objective

One concrete, testable outcome.

## Non-goals

- Explicit exclusions.

## Evidence and source of truth

- Relevant source files, ROM addresses, decomp functions, and existing tests.
- ROM requirement: yes/no.

## Owned paths

- Exact paths the worker may create or edit.

## Forbidden paths

- Shared decoders, public APIs, integration files, and other workers' claims.

## Interface contract

- Inputs:
- Outputs:
- Invariants:
- Compatibility requirements:

## Acceptance commands

Run from `/opt/git/gen1recomp` unless the command says otherwise.

```sh
# Targeted unit test
# Syntax/load check
mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

## Baseline

- Record `git status --short` before editing.
- Existing dirty paths are not worker-owned unless listed above.

## Risks and open questions

- Known uncertainties that must not be guessed through.

## Required handoff report

- Status:
- Files changed:
- Diff summary:
- Commands and results:
- Behavioral evidence:
- Limitations:
- Unresolved assumptions:
