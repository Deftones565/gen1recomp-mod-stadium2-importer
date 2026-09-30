# What runs as native ROM code (the MIPS VM) — 2026-09-29

> **Update 2026-09-30: nothing runs in the VM during play any more.** The
> four runtime families below are Lua ports, and the VM moved from `lib/` to
> `tests/support/stadium2_battle_fx_mips.lua`, where it is only a test oracle
> (the user's direction: "Test oracle is fine since it gets outputs"). See
> "Ported 2026-09-30" at the end. The original inventory follows.


Local session. `lib/stadium2_battle_fx_mips.lua` is a small MIPS III + FPU
interpreter: it runs chosen Stadium 2 functions from the player's ROM over a
sparse private memory. It is not an N64 emulator (no RSP/RDP, audio, timing,
OS or input); calls it should not make are replaced by Lua hooks. The mod
uses it two ways.

## 1. Run during play (the ROM code is the implementation)

| Family | Moves | Module | ROM entry points | Hooks (what the port supplies) |
| --- | --- | --- | --- | --- |
| 3 (stochastic) | Razor Leaf (75) | `stadium2_battle_fx_stochastic.lua` | `84157AB0` init, `84166A64` draw | `84109780` origin, `841098FC` target, `84109544` scale, `841094EC` finish signal, `84156BA0` no-op; libc sin/cos in Lua |
| 15 (stochastic) | Petal Dance (80) | same | `84157CB0`, `84166A64` | same |
| 7 (terrain grid) | Surf (57) | `stadium2_battle_fx_terrain_grid.lua` | `8415A9E4` init, `8415AC64`, `8415AD58` update | owner anchor X, camera eye/focus/projection, `841094EC` signal |
| 8 (textured stream) | Hyper Beam (63) | `stadium2_battle_fx_textured_stream.lua` | `84169618` draw, family init/update | `84109780` origin, `841094EC` signal, `841094A4` camera struct, `84166F60`/`841670A8`/`841677C4` |
| 13 (textured stream) | Ice Beam (58) | same | same | same |
| 20 (Tri Attack) | Tri Attack (161) | `stadium2_battle_fx_tri_attack.lua` | `84169B80`, `8415C530`, `84158768`, `8415DAE4` update, `8415DBBC` draw | `84109780` origin, `841569E0`, `8415D430`, `8416A050` |

Each keeps a persistent VM per effect instance, steps it once per 30 Hz
tick, and reads vertices/colours back for the renderer.

## 2. Test oracles (Lua ports checked against the ROM)

These families and helpers are ported to Lua; their tests run the ROM
function in the VM on the same inputs and compare:

| Test | ROM functions | What is checked |
| --- | --- | --- |
| `common_anchor_rom` | `84104A00` | common-particle anchors |
| `height_ribbon_rom` | `8411EF90`, `8415BD48` | species height, ribbon update |
| `context_scale_rom` | `8411E358` | per-context scale |
| `four_stream` | `8415809C`, `841580C8`, `84164280` | four-stream family |
| `needle` | `84158588`, `84165C2C`, `84165CC0` | Needle family (Poison Sting etc.) |
| `radial` | `8415C530`, `8415DAE4` | radial families |
| `swift` | `84157128`, `84162660`, `84162C88` | Swift |
| `screen_rom` | `841027B4`, `841076B8` | screen particles |
| `direction_rom` / `scaling_rom` | `841013F4`, `84101AF4`, `84105F10` | direction and scale controllers |
| `model_animation_rom` | `8003E6DC`, `8410291C` | model animation counter, completion |
| `battle_state_rom` | `841083B0`, `84101D54`, `84106F34` | opcode 16 conditions, alpha gate |
| `surf_material_rom` | `84101D54`, `84106F34` | Surf material |
| `dynamic_anchor_rom` | `84102750` | dynamic anchors |
| `tri_attack`, `textured_stream`, `stochastic`, `terrain_grid` | as above | the runtime VM families against fixtures |

## Direction: port everything to Lua, then remove the VM

User direction (2026-09-29): all native assembly is to be ported to Lua and
the VM removed eventually. Until then the VM is a test oracle only:

- New native logic is written as a Lua port, never run in the VM during
  play. Each port gets a test that runs the ROM function in the VM on the
  same inputs and compares the output.
- Porting backlog (VM still runs during play): families 3/15 (Razor Leaf,
  Petal Dance), 7 (Surf), 8/13 (Hyper Beam, Ice Beam), 20 (Tri Attack). Their
  existing VM tests become the acceptance tests for the ports.
- When no runtime module requires `stadium2_battle_fx_mips.lua`, it moves to
  test-only use; it is removed once every oracle test has been replaced by
  recorded reference data or is no longer needed.
- The battle camera is ported to Lua from the start, checked against
  `84111774` (the camera program runner) and the shot setup in the VM; see
  `battle-camera.md`.

## Ported 2026-09-30 (local session)

Sources: US assembly (pret/pokestadiumgs `c0e10f23`); every function below
is still GLOBAL_ASM in michiiik/pokestadiumgs `1b6dc17c`. Each port works on
Stadium's own memory layout (`lib/stadium2_native_memory.lua`), so its
display list and vertices are byte-identical to the ROM's and the modules'
existing decoding is unchanged. Each has an oracle test that runs the ROM in
the VM on identical memory and compares every byte, every frame, of whole
effects. That matches ROM execution; the moves still need a visual check.

| Family | Port | ROM functions | Oracle test |
| --- | --- | --- | --- |
| libultra | `stadium2_libultra.lua` | __sinf, __cosf, sqrtf, guMtxF2L/L2F, guMtxCatF/L, guMtxXFMF, guTranslate, guScale, guRotateF, guNormalize, guRotateRPYF, guRotateRPY (8007D454) | `stadium2_libultra_rom_test.lua` |
| 3 / 15 Razor Leaf, Petal Dance | `stadium2_battle_fx_stochastic_native.lua` | 84157AB0/ADC, 84157CB0/CDC, 84166130, 84166270, 841665D4, 8416691C, 84166A64, 8416654C | `stadium2_battle_fx_stochastic_native_rom_test.lua` |
| 20 Tri Attack | `stadium2_battle_fx_tri_attack_native.lua` | 84158840/874, 84158768, 8415C530, 8415C644, 8415DAE4, 8415D4C4 (all modes), 8415DBBC (mode 5), 8415D430, 84169B80/BA8/C74/DBC, 84169F18's spark size | `stadium2_battle_fx_tri_attack_native_rom_test.lua` |
| 7 Surf | `stadium2_battle_fx_terrain_grid_native.lua` | 8415A9E4, 8415AD58, 8415A364, 8415AC64, 8415ADE0, 84159D30, 84159FA8, 80070BA4, 80070C14 (atan2 8000B3B0 through the camera port) | `stadium2_battle_fx_terrain_grid_native_rom_test.lua` |
| 8 / 13 Hyper Beam, Ice Beam | `stadium2_battle_fx_textured_stream_native.lua` | 84158E24/E58, 84159C2C/C6C, 84158C4C, 84159A50, 841597AC, 84168540, 84168680, 84169040, 84168CA4, 84169618 (mode 0), 84168C18 | `stadium2_battle_fx_textured_stream_native_rom_test.lua` |

What changed besides the engine of execution:

- The old runtime hooked several ROM routines with host stand-ins:
  `math.sin`/`math.cos` for __sinf/__cosf (Razor Leaf, Surf, the streams),
  for Tri Attack's 8415D430 and the streams' 84168C18, and for Tri Attack's
  spark size; Surf's normalize, cross product and guScale were rewritten by
  hand and its atan2 (the slope angle) forced to 0. The ports use the exact
  ROM routines, so results now match the ROM where they differed slightly
  before (the leaf test diverged within six frames with `math.sin`).
- Boundaries that stay host-side, the same as before: anchors, the end
  signal, the injected RNG, the display-list arena; Tri Attack's
  camera-facing spark submit (8416A050); the streams' combiner and
  sub-list emitters (800710A8, 84169344, 84169214, skipped as before) and
  Hyper Beam's core beams (84166F60 / 841670A8 / 841677C4, already
  `stadium2_battle_fx_beam.lua`; the ported 841597AC hands it the ROM
  call's exact registers and stack words).
- Not ported (never reached by these moves): Tri Attack's draw modes 0-4
  and the stream draw's mode 1 (84168B00). Both fail loudly if reached.
- ROM quirk kept: 84168CA4 reads its frame's word at sp + 0xA8 without
  writing it. In the effect's own call chain that stale word is the last
  spawner's stack argument (0x19) or, after a draw with live slots,
  84169618's loop word (0x5000). The port keeps that one word at its ROM
  address (`S.STALE`), so the waiting nodes' wave phase matches the ROM.
- VM fix: `cvt.w.s` now honours FCSR's rounding mode. The streams' fade
  alpha sets round-toward-zero first; the VM had rounded to nearest, so it
  disagreed with the port (and the hardware) on that byte.

Speed (the same update + draw sequence for 60 frames, `os.clock`, LuaJIT,
this machine): Razor Leaf 12.4 -> 1.9 ms/frame, Tri Attack 4.7 -> 1.3,
Surf 1.7 -> 0.85, Ice Beam 2.5 -> 0.76. The ports' remaining cost is mostly
the byte-table native memory.
