# Native memory: what it is and how to make it cheaper (2026-09-30)

Local session. A note for later; nothing here is scheduled yet.

## What it is

`lib/stadium2_native_memory.lua` is a byte store keyed by address:

- Writes go to a Lua table, one entry per byte.
- Reads fall back to read-only ROM images at their N64 addresses (fragment
  79 at `0x84100000`, main code at `0x80000400`), then to 0.
- Helpers read and write big-endian 8/16/32-bit integers and floats.

It does not emulate the N64: there is no RDRAM, TLB, cache, DMA or hardware
registers, and nothing executes. It is a data layout. The Lua ports keep
their working state at the addresses and offsets the game uses.

## Who uses it

These are the only users. Everything else in the battle FX runtime (the FX
bytecode interpreter, particles, the Poke Ball send-out and recall) keeps
its state in ordinary Lua tables.

- The ported effect families: `stadium2_battle_fx_*_native.lua`, driven by
  the stochastic, Tri Attack, terrain-grid and textured-stream modules.
- `stadium2_libultra.lua`, for fixed-point matrices.
- The STADIUM camera: `stadium2_battle_camera*.lua`.

## Why it was chosen

1. Byte-for-byte proof. Each port's oracle test runs the ROM function in the
   VM (`tests/support/stadium2_battle_fx_mips.lua`) on identical memory and
   compares every byte, so a layout match makes the check exact.
2. The modules' existing display-list and vertex decoding kept working
   unchanged when the VM was replaced.
3. ROM quirks stay exact. Examples: pointers stored in ROM data, and the
   stale stack word the stream node update reads (`S.STALE` in
   `stadium2_battle_fx_textured_stream_native.lua`).

## Cost

Every field access is a few table lookups plus a big-endian conversion, and
floats go through an FFI union. This is most of the ports' remaining
runtime. Measured (60 frames of update + draw, `os.clock`, LuaJIT, the
local machine): Razor Leaf 1.9 ms/frame, Tri Attack 1.3, Surf 0.85, Ice
Beam 0.76. The VM, for comparison: 12.4, 4.7, 1.7 and 2.5.

## Fixes, in order of effort

a. **An FFI byte buffer behind the same API.** Allocate one `uint8_t[]` per
   memory region (or a sparse set of pages) and implement `u8/u16/u32/f32`
   and the setters with direct indexing and byte swaps, keeping the
   ROM-image fallback for unwritten pages. The ports and their tests stay
   unchanged and byte-exact. This is the cheapest and safest speedup.
b. **Cache hot fields in locals.** Inside the per-node and per-vertex loops,
   read each field once into a local and write it back once. This is the
   same memory and the same results, with fewer calls. It can be combined
   with (a).
c. **Plain Lua structures.** Rewrite the ports on Lua fields
   (`slot.nodes[j].delay`) and give the tests a small serializer that
   writes that state into the game's layout for the byte comparison. The
   modules would read the Lua structures directly instead of decoding
   display lists. This is the fastest and most idiomatic option, and the
   most work: one family at a time, each gated on its oracle test.

Recommendation: (a) first, since it is cheap and keeps everything proven.
Then (c) per family, if the user prefers ports that do not mirror the
game's memory.
