# Shared ribbon lifecycle

**Update 2026-09-29: family 29 implemented** (entry 261, Bind/Wrap residual
damage). US assembly, pret `c0e10f23`: wrapper `8415703C` passes `8415BBA0`
the same colour arguments as 23's `84156F50` (100,200,255 / 0,100,200); its
setup anchor is `841569C0` → `84109B1C` (the owner's context marker:
`8411E244` then `8003C9B8`, then `8411DCCC`) and its scale `841569A0` →
`841095DC` (`8411E358` context table × `D_84188E2C` = .01). Update
`841570B4` calls `8415BD48(1)`: `a0` only selects the per-tick anchor
re-sample, `84109B1C` for 1 and the joint sampler `8410971C` for 0; the
rest of the kernel is shared. The port uses the owner's anchor, and
`Dispatch.contextScale(261, owner context bytes)` for the scale (byte 0x21;
0.4–2.55 over all species, none zero). Approximation, reported as
`approximate-ribbon-context-marker`: `8411E244`'s marker choice is not
ported, so the owner's move-row marker stands in (as for 23's joint).
ROM test: `stadium2_battle_fx_ribbon_rom_test.lua` (entry 261).


Implemented retail families 23, 26 and 27 through the persistent lifecycle
manager, renderer-neutral packets and the battle/viewer player. US ROM source:
initialization 8415BBA0, update 8415BD48, draw 8415C2E0; wrappers
84156F50, 84157650, 84157740. Reference pret revision:
c0e10f23d90cc4f335b654711f13e53c2c07323b.

The alternate dispatches of moves 20, 35, 50, 81 and 132 reach these families.
The viewer's O control selects alternate dispatch. Primary dispatch behavior
is unchanged by this lifecycle implementation.

The kernel retains 400 records, grows six pairs per 30 Hz update up to 200,
resets its counter to 18 after 30 and terminates on its 21st rollover (frame
291). Radius changes, two vertical waveforms, ground clipping, signed vertex
truncation and triangle order follow the native routines. Colors come from
each wrapper; draw alpha is a constant 200, independent of the state alpha.
The ROM's 8x16 IA8 texture at 84187418 and combiner FC309661/552EFF7F are
decoded separately from simulation. Draw reuses a fixed mesh, uploads new
positions/indices only when the simulation frame changes, and releases the
mesh on expiry. Explicit callback/model/renderer resolvers retain precedence.

Limitations: the host adapter places the ribbon at its battler slot. Native
8410971C samples an animated model joint; exact joint mapping is not yet
integrated. Callers can supply lifecycleAnchor/resolveAnchor and lifecycleScale;
the default scale is 1 rather than a decoded battler field 661 times .01.
Sin/cos currently use host math rounded to float32, not a bit-exact port of
the N64 libultra polynomial. Other lifecycle families (including unused 29)
remain unsupported unless a resolver is supplied. This is not full native-FX
parity.

Validation: ribbon kernel tests cover timing, colors, state isolation, topology,
snapshot purity and callback termination. ROM integration tests cover decoded
texture bytes, all five routes, renderer construction, mesh reuse and disposal.
GPU submission is stubbed in tests; no visual or pixel comparison is claimed.
