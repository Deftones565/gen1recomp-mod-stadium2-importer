# Grimer and Muk callback ownership — 2026-09-26

Status: implementation and ROM-backed regression complete; user visual retest
pending. Species 88 and 89; no battle move IDs or battle mechanics changed.

Sources: supported US ROM and michiiik/pokestadiumgs master checkout
`204b7d8b88a27f920d2b538cc5bca278d00aed79`. `src/229E0.c`'s
`Geo_NodeDisplayList` (`func_8003C080`, confirmed by `linker_scripts/us/aliases.ld`)
submits a node's display-list pointer at +0x18. Fragment 26's
`func_81005DB4` (descriptor `0x81000048`) allocates 0xF0 bytes, publishes that
pointer at node +0x18, and calls `func_81005B50`. The latter remains
GLOBAL_ASM; its tile loads and material were checked against the ROM landmarks
in `stadium2_dual_texture_material_audit.lua`, not reconstructed from nearby C.
The material at `0x810061B0` uses combine words `FC262A04 1F1893FF` and two
32x32 RGBA16 images.

Muk's decompressed model fragment (base `0x8FF00000`) demonstrates the bug:

| Offset | Command | Meaning |
| --- | --- | --- |
| `0xD7D0` | `23010000 ... 0004FFFF` | Local animated eye material |
| `0xD7E0` | `22010000 8FF0C0C0` | Eye display list |
| `0xD7E8` | `22010000 00000000` | Separate empty display-list node |
| `0xD7F0` | `08000000 81000048 ...` | Install generated slime list on that empty node |
| `0xD7FC` | `22010000 8FF0C0F0` | Following body geometry |

`Model:runDL` returned on the null pointer before replacing its last-draw
record. The callback consequently reassigned the earlier eye draw. Subsequent
merging combined 12 eye vertices/8 triangles with 41 body vertices/27
triangles. Clearing the last-draw record even for a null node keeps the eye
local and separates those surfaces. Muk now has 30 material groups instead of
25, still exactly 701 triangles; Grimer retains 24 groups and 700 triangles.
All 20 Muk callback sites now have consumers (previously 19); all 16 Grimer
sites remain consumed. No geometry was invented or removed.

The initial generated body draws also inherited the prior mouth texture's
cutout classification. Grimer's 13 base triangles at callback `0x10044` and
Muk's 41 at `0xD328` were still treated as decals and could sample the mouth
image. Active slime draws now require their generated texture and derive alpha
classification from its RGBA bytes. Their generated tiles are opaque in both
normal and shiny packs. Local mouth, tongue and eye draws remain separate when
the graph specifies a local material. Inherited texture-animation channels no
longer exempt generated body draws from the callback's texture load.

This replaces reliance on merged vertex counts/atlas dimensions for the live
render path. The fixes happen at extraction and existing material selection;
they add no per-frame geometry work. No performance benchmark was run.
Cache S2IMP62 invalidates older exported callback assignments automatically.

Validation, run from `/opt/git/gen1recomp`:

- `STADIUM2_REQUIRE_ROM=1 luajit mods/STADIUM2_IMPORTER/tests/stadium2_slime_model_rom_test.lua`:
  passes normal/shiny topology, native null-node command words, generated
  texture routing, opaque bases, and four local eye expressions. Running it
  with the pre-change fragment module fails on stale alpha classification.
- `stadium2_dual_texture_material_audit.lua`: 36 callbacks, 36 consumers,
  36 routes, 45 generated surfaces, zero incorrectly classified decals; pass.
- `stadium2_render_parity_audit.lua`: all 251 models, 559 callbacks,
  phase-5 203/203 and material FX 36/36; pass.
- `stadium2_renderer_test.lua`: 138 standalone and 199 GPU-stub checks pass.
  `stadium2_core_test.lua`: 21 pass.
- Fresh LOVE renders of both species, bind/idle, front/back/underside: inspected
  locally; eyes, body atlas ownership and lower surfaces corrected. This is
  importer render verification, not a native frame capture or user confirmation.
- Required `STADIUM2_REQUIRE_ROM=1 tools/run_battle_fx_worker_checks.sh`:
  ROM audit and checks through screen-viewer pass; stops at the existing
  `stadium2_battle_fx_sequence_test.lua:238` dispatch-hit-frame assertion.
  Reproduces with pre-change fragment/renderer modules. The remaining 12
  runner tests were run separately and all pass.
- Full DSM roundtrip: all 251 ordinary species build and pass assertions;
  the audit still fails on special Egg species validation. The same failure
  reproduces with the pre-change modules and original roundtrip audit.
- `git diff --check`: passed before and after the changes.

The battle-FX missing-implementation sweep was not regenerated: model material
ownership does not change its move implementation counts. Pre-existing changes
and concurrent README/integration documentation work were preserved.
