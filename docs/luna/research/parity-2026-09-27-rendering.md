# Rendering and material parity audit — 2026-09-27

This is a research-only handoff. It records confirmed ROM/decomp behavior,
current importer behavior, and the remaining visual-parity questions. It does
not claim a visual fix or change runtime code.

## Evidence

The current fork checkout consulted was
`/tmp/stadium2-parity-decomp-20260927` at
`0ed78d46e9cd11432f217203675a839efcb1cc1c` (fragment 79 C now includes the
implementations of `84103394` and `84103478`). The older supported-US source
checkout is `/opt/git/pokestadiumgs` at
`c0e10f23d90cc4f335b654711f13e53c2c07323b`; its US assembly was used for
the still-`GLOBAL_ASM` callers and transform routines. The requested earlier
fork revision `204b7d8b88a27f920d2b538cc5bca278d00aed79` has the same relevant
`36F8B0`, `3749B0`, and `3CE960` declarations; the newer fork is cited here
because it is the current source of truth supplied for this audit.

## Confirmed second-pass behavior and current mismatch

The retail functions are not interchangeable passes:

* `func_84103394` (`0x84103394`, fork C) scans all `0x12C` slots at
  `D_8418C950`, requiring the slot live byte `+0x98`, runtime mask
  `0x102800` clear, and runtime flag `0x1000` set. It derives the layer as
  `3` when the child object at slot `+0x10` has bit `2` at child `+8`, else
  `0`, and only calls `func_841031F4` when that equals
  `D_80094910+0x18`.
* `func_84103478` (`0x84103478`, fork C) scans the same 300 slots with
  `0x100800` clear, `0x1000` and `0x2000` set. If runtime bit `0x4000` is
  set it calls `func_841032F0` (the screen-quad path); otherwise it calls
  `func_841031F4`. This is a distinct 2D/overlay-capable pass, not merely a
  repeat of the ordinary draw.
* The US assembly caller `func_84105630` (`0x84105630`,
  `fragment79_3749B0/func_84105630.s`) enters the draw branch for dispatch
  case `3` (`jtbl_84188C30[3] == 0x84105688`). It calls `84103394` first,
  emits `guOrtho` into `D_84190074+0x5B80` with the 320x240 bounds, then calls
  `84103478`, and finally restores the display-list state. The wrapper
  `func_8410580C` (`0x8410580C`) passes its third argument as this dispatch
  case; callers include `8410A608`, `8410A6A4`, `8410A9D4`, `8410A884`, and
  `8410AA18`.

Every mode-1 common emission gets `0x1000` in `841072BC`, but the current
player has no equivalent of the retail layer selector or the `0x2000/0x4000`
gates. `Player:draw` sends common packets through the normal renderer
(`lib/stadium2_battle_fx_player.lua:621-710`), while `Player:drawOverlay`
handles decoded screen packets and native-object screens as a separate
presentation callback (`:715-760`). This leaves the mode-1 second-pass mapping
and its layer ordering unmodelled.

The following is the ROM-backed mode-1 enumeration, rather than the viewer's
screen-capable worst-move list. I loaded the supported
`baseroms/stadium2.z64` with `Rom.normalise`, called
`FxRom.catalog`, then for each move `1..251` walked
`primaryDispatch`, `alternateDispatch`, and (when present) `variantDispatch`;
I marked a move/bank when a routed program record had
`record.emitter.mode == 1`. The counts below are move IDs with at least one
such record, followed by the number of mode-1 records (duplicate programs
within a bank are counted as records). The alternate filename
`baseroms/Pokemon Stadium 2 (USA).z64` has the same SHA-1
`d8343e69a7dc63b869cf6361d87cde64444281d3`, so both local supported-ROM
names resolve to the same bytes.

* primary bank: **99 moves / 200 records (91 routed programs)** — move IDs
  `7,8,9,10,14,15,22,28,34,36,37,38,40,41,42,52,53,54,55,56,57,58,60,61,62,63,66,73,76,77,78,79,82,83,84,85,86,87,99,102,105,106,108,111,112,113,114,115,116,117,120,123,126,127,131,135,139,140,143,144,145,147,151,153,154,159,160,163,164,166,174,176,182,187,188,189,190,204,205,206,207,208,209,210,213,215,217,219,223,225,226,229,232,234,235,236,239,240,250`.
* alternate bank: **159 moves / 589 records (123 routed programs)** — move IDs
  `1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,19,21,22,23,24,25,26,27,28,29,30,31,32,33,34,36,37,38,39,40,41,42,44,49,51,52,53,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,73,75,76,77,78,79,80,82,83,84,85,86,87,88,89,90,91,92,98,99,117,119,120,121,122,123,124,125,126,127,128,129,130,131,136,139,140,143,145,146,152,153,154,155,157,158,161,162,163,164,165,167,168,172,173,175,177,179,181,183,185,188,189,190,192,196,198,200,201,205,206,209,210,211,214,216,217,218,220,221,222,223,224,225,228,229,231,232,233,237,238,239,240,242,243,245,246,249,250,251`.
* variant bank: **3 moves / 8 records (3 routed programs)** — move IDs `76,91,143`. Their
  variant route values decode from the six-entry variant table as
  `76:0x0052`, `91:0x0025`, and `143:0x007A`.

This enumerates routes that contain mode-1 emitters; it does not claim that
all of those particles are selected in every battle context or that every
mode-1 particle reaches the 84103478 screen-quad branch. The current player
still needs a ROM-derived layer/flag trace before a smaller per-move affected
set can be claimed.

There is a separate ordering mismatch in the current overlay bridge. Retail
`84103478` iterates slots from index 0 through 299. `Player:drawOverlay`
currently sorts `screens.screenPackets` by `born` before drawing. Allocation
cursor movement and slot reuse mean pool order is not generally birth order.
This is a confirmed execution mismatch for mixed screen particles; its pixel
impact is unverified. The existing audit note correctly treats pool-slot reuse
order and GPU output as open.

## Inherited combiner and environment state

Retail display-list RDP state is persistent. `func_841031F4`
(`0x841031F4`) runs the material callback, then `84102E84`, then the entry
display list; `func_84102E84` reads the entry halfword at `+6`. The callback
and display-list state can set combiner (`G_SETCOMBINE`), primitive
(`G_SETPRIMCOLOR`/`G_SETLODFRAC`) and environment (`G_SETENVCOLOR`) state,
and state remains available to subsequent lists.

The importer now does several correct pieces of this contract: `fragment.lua`
copy-on-write tracks `rdpState` through display-list commands, `rdpMaterial`
retains `displayListState`, and `Renderer:currentMaterial` merges callback
colour state into an inherited display-list material when the callback has no
combiner. `Renderer.surfaceLit` also correctly disables scene lighting when a
phase-5 combiner does not consume SHADE, matching the Sandstorm near-black
follow-up.

The remaining gap is the state boundary between separately loaded/drawn
models. When no local `G_SETENVCOLOR` was seen, `rdpMaterial` leaves
`environmentColor` nil (`lib/fragment.lua:1567-1581`) and the renderer sends
`{1,1,1,1}` (`lib/renderer.lua:2620-2665`). Retail would inherit the
environment value left by the preceding submission. The fallback is therefore
confirmed from the ROM/state model. The white jaw result is a historical
viewer observation recorded for Vice Grip 11, Guillotine 12 and Bite 44 in
`battle_FX_bugs.md:3-14`; it is not a new user confirmation in this audit.

Wind/Strength remain an open diagnosis, not a confirmed current failure. The
bug log's isolated-viewer follow-up lists Razor Wind/Gust/Whirlwind/Roar and
Strength as needing viewer checks (`battle_FX_bugs.md:183-196`), but that does
not establish that their current submissions are wrong or that they take this
fallback. A fresh extraction plus submission-state trace is required before
assigning those moves to this gap. Likewise, Swords Dance 14's latest note
states that the chrome callback texture and environment mapping were fixed and
await visual retest (`battle_FX_bugs.md:183-186`); the earlier compiled-layout
gap is not evidence that Swords Dance is currently affected. The general
cross-model inheritance question remains open for compiled layouts whose
prior submission cannot be reconstructed from the isolated model.

Compiled-layout paths with no colour block remain the same class of open
question. The audit's gap 10 describes `810024E0`/`841028DC` submissions:
a callback may submit colours while the prior combiner remains in effect.
The current model extractor preserves a combiner only when it was decoded in
the extracted model's local state; it cannot prove the prior model or prior
render-layer state. This is not evidence that Swords Dance 14 is currently
wrong: its chrome callback correction is recorded above and still awaits
visual retest. Do not fill an unresolved prior combiner with a default.

## Texture and render-state findings

The resource decoders have explicit retail format evidence:
`Resources.beamTexture` (I4/RGBA16 at
`lib/stadium2_battle_fx_resources.lua:194-224`)
handles the `format=4,size=0` 32x32 I4 beam images and `format=0,size=2`
32x32 RGBA16 images; `Resources.waveGridTexture` decodes the family texture
exports as RGBA16 (`:174-192`). The recent bug-log corrections establish that Razor Leaf
75/Petal Dance 80 use RGBA16 sprite data, Swords Dance 14 uses its chrome
callback texture, and Take Down 36/Double-Edge 38 use intensity as alpha for
I4/I8 streaks. These are decomp/resource-confirmed fixes, awaiting user
visual retest; CPU decoding alone is not GPU pixel parity.

Direct shape render state is decoded from `84102E84`: low values 1, 4 and 6
select the retail opaque, cutout and translucent blender families; bits 0x40
and 0x80 select the four variants; depth compare/write comes from the emitted
other-mode word. `RenderMode.decode` records this at
`lib/stadium2_battle_fx_render_mode.lua:28-64`, and the renderer applies it
per primitive. Retail low value
0x3F calls `84102D38` to bind the owner texture, but no supported retail
entry 1..301 uses it, so its lack of implementation is not an affected move.
Anti-aliasing bits and exact GPU coverage behavior remain unverified.

## Screen and wave transforms

Common screen particles are now structurally matched to `8410383C`,
`841038F4`, `841039AC`, and `841039F4` from the US assembly: angle index is
`(u16 angle)>>4`, position components are signed 16-bit values, mode 5 uses
uniform scale, and mode 6 scales only the second model-space axis. The player
uses the native 320x240 orthographic projection for the overlay. Missing ROM
trig tables produce a diagnostic instead of a guessed transform.

Wave families 9, 10 and 11 cover moves 95, 103, 173, 45 Growl, 48 Supersonic,
134 Kinesis, 47 Sing and 195 Perish Song. `8415FC60` is still `GLOBAL_ASM` in
the fork and the US assembly proves its camera-relative construction: it
normalizes focus minus eye, uses `105/(FOV/30)` for the displacement beyond
focus, and passes the result to the native matrix helper. `WaveGrid.matrix`
implements that placement and the resource mapping (family 9 export 38;
families 10/11 export 36), but uses host floating-point camera basis/matrix
construction. Camera orientation and texture-generation pixel parity remain
unverified. The wave finish signal is separate from this transform and must
come from the native presentation signal.

The user-requested “whole camera” behavior for 45, 47 and 48 is a requested
extension. Retail draws these as lifecycle wave-grid geometry placed from the
camera state (`lib/stadium2_battle_fx_wave_grid.lua:115-134`); this audit did
not determine whether that geometry fills the camera in every native view.
First establish native coverage from the ROM path. If the requested behavior
goes beyond that native coverage, keep it as a separately named non-native
extension while reporting the native wave geometry and placement separately.

## Status and next actions

Confirmed ROM/decomp gaps: inherited cross-model combiner/environment state;
missing common-particle layer/second-pass state; overlay order differing from
the 300-slot iteration (`Player:drawOverlay`, lines 735-741). Confirmed
implementation paths: direct shape transforms, retail blend/depth decode,
resource format routing, and mode-7 screen initialization. Unverified: the
per-move 84103478 layer assignment, final GPU pixels, camera/wave matrix
rounding, anti-aliasing coverage, wind/Strength state diagnosis, and user
visual retests.

The targeted mode-1 enumeration above does not regenerate the ROM-wide sweep.
Root should update the full sweep in
[`docs/battle_fx_missing_implementation_audit.md`](../../battle_fx_missing_implementation_audit.md)
only after its own count review and a targeted renderer check for pool-order
reuse. No runtime files were changed here.
