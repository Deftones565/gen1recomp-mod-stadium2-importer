# Proposal: a Stadium record translation layer (2026-10-02)

Status: proposal, agreed in principle by the user; to be started after the
current status-particle work. Not implemented.

## The problem

Stadium 2 itself has three layers:

1. the battle engine (fragment79_393CA0) decides what happens;
2. it queues event records (84134CBC / 84134A6C: 0x280 bytes each: code,
   side, move, result byte, per-battler HP / status / flags) in a ring
   (D_84195280);
3. the presentation (camera, battle FX, battler states) plays one record at
   a time, gated by 84135778.

The port has layers 1 (Gen1Recomp's Gen 1 / Gen 2 engines) and 3 (ported
from the ROM). Layer 2 exists only implicitly, spread across
`gen1_battle.lua`, `gen2_battle.lua`, `battle_scene.lua` and
`stadium2_battle_camera.lua`. Symptoms found in this work:

- Logic written twice, differently, per host: the turn handoff (Gold: engine
  hooks; Red: a command round), the record flags, the status byte, the
  charge state, the record HP, the first mover.
- Records filled from live state at the wrong moment: the record HP (a
  knocked-out Pokemon would have been hidden during its own last hit), the
  charge turn's own record (built before its flying bit is set).
- Stadium events that never happen because nothing owns "which records
  would Stadium have queued here": the handoff (7 / 8 / 9, now added),
  "fell asleep" / "frozen" hits (0x0C / 0x0E), the send-out of an asleep
  or frozen Pokemon, Minimize's flag.
- Host text matching and camera calls in the same functions, so one new
  event touches several files.

## The proposal

```
Gen 1 / Gen 2 engine
  -> fact adapter (per host)            what happened, in host-neutral facts
  -> record translator (one, shared)    the records Stadium would queue
  -> record player (the 84135778 gate)  one record at a time
  -> presentation                       camera, battle FX, battlers
```

- Facts (per host, the only host-specific part): action started, move used,
  hit / miss / no effect and its result, damage, status inflicted / cured,
  faint, switch / send-out / drag-in, charge, weather, stat change, item,
  and so on. Engine events first, host text only as the fallback the
  trigger rule allows.
- Translator: a port of how Stadium's engine builds records: 84134CBC /
  84134A6C (fields and the snapshot moment), 841343FC (turn order and the
  handoff), 84124604 / 841246AC (hit and miss codes), 8412C47C (charge
  turns), the status and residual queue sites. Each record is a snapshot
  at its queue moment, as in the ROM.
- Record player: the 84135778 gate (timer, new-event flag, HP bars, text)
  holding host presentation; the only place that decides when the next
  record starts.
- Presentation consumes records only and never reads host battle state.

## What it buys

- Correct by construction: queue moments and field values decided once,
  as the ROM decides them.
- Testable against the ROM: the translator can be compared with the
  engine's own queue code in the VM oracle (same facts in, same records
  out). The current scattered layer cannot be tested as a whole.
- Explicit gaps: a fact a host cannot supply (the minimized flag) is
  reported in one place, never defaulted inside a camera function.
- A new host or host version needs only a new fact adapter.

## Costs and risks

- A real refactor: today's entry points (`stadiumCameraAttack`,
  `turnCheck`, `chargeTurn`, `hit`, `sendOut`, `statusEvent`, ...) become
  record consumers.
- The hosts present differently (Gold resolves a whole turn first; Red runs
  live): the translator and the record player must serve both, and the
  presentation holds move into the record player.
- It must stay a description of what happened: the host decides outcomes.

## Plan (incremental, behaviour kept at each step)

1. Design note for review: the record format, the fact format, and a table
   mapping each fact to Stadium's queue sites (addresses, decomp commit).
2. Move what exists into the translator unchanged (record flags, status,
   HP, handoff, first mover, charge records, hit codes); current tests keep
   passing.
3. Switch consumers one event family at a time (attack / hit, then status,
   send-out, faint ...), each with VM-oracle tests where the engine code
   allows.
4. Fill the gaps the translator makes visible.
