# Stadium 2 decomp cross-check, 2026-09-17

Reference: https://github.com/michiiik/pokestadiumgs at
`2b44e8fa04aba7ba70493d1ad909cea481517394`,
`src/fragments/79/fragment79_3C60B0.c`.

This corrects the earlier timer interpretation in lifecycle-families.md and
lifecycle-rendering.md. The earlier audit inverted the spawn windows and
mistook direct -1 returns for arguments passed into the update helper.

| Family | Spawn cadence after init | Direct termination |
| --- | --- | --- |
| 2 | Every 3 ticks below 1770 (last spawn 1767) | 1801 |
| 4, 6, 21 | Every 7 ticks below 120 (last spawn 119) | 181 |

These correspond to primary Swift, Bind/Wrap/Constrict, String Shot/Spider Web,
and Disable routes. Existing slots update during the drain interval. The
callback returns before calling the shared update helper at termination.
Counters use signed 16-bit wrap, matching the native sh/lh sequence.

Verification reads the actual US ROM instructions at each callback's +20,
+24, +30, +34 and +38 offsets (hex): termination comparison, branch-likely,
-1 return value, spawn-window comparison and skip-spawn branch. Unit tests
exercise all four cadence windows and expiration boundaries.

This fixes lifecycle scheduling; it does not implement the missing geometry
kernels. Several remain GLOBAL_ASM in the new fork, including 84163B4C and
84165CC0. Do not count these four families as newly renderable.

## Swift lifecycle implementation

Family 2 now has init/update/draw integration in the main mod and its existing
Koffing/Croconaw viewer player path. `stadium2_battle_fx_swift.lua` implements
the US 14-slot pool, raw guRandom remainders, 10-node trail histories, first
11 ticks of vertical drift, subsequent directed motion and X acceleration,
30+10-tick slot lifetime, and the native controller finish window. Histories
advance once per simulation tick; repeated host draws cannot mutate them.

The new fork supplies `TexturedRibbonSheet_UpdateRecord` in
`fragment79_3D0D70.c` and the move scale assignment in `fragment79_37A6E0.c`.
Retail instructions supplied the remaining constructor and controller details.
Stadium 1's analogous source is NOT interchangeable: the US Stadium 2 pool
has 14 slots, export 39 is the star texture, UV maxima are 1984, and its
star environment alpha is 20. Draw state is checked against 84187848..84187930.

The adapter resolves the target actor anchor separately from beam target
height and reads scale from the move dispatch byte +0F, multiplied by .01f.
Native world coordinates are retained during simulation because world X
selects acceleration direction; geometry is then converted to the player's
source-relative frame. Missing imported anchor/profile/scale data is diagnosed.

The new test executes retail 84157128/84162798/84162C88 instructions in the
isolated MIPS interpreter and compares every live node, RNG-dependent state,
slot phase and completion across three scales and both source directions.
Actor endpoints, scale, signal and RNG are controlled hooks. It also exercises
the real resource decoder, player, renderer, mesh reuse and disposal headlessly.
The existing interpreter's FPU round-to-nearest expression was corrected.

This adds one renderable lifecycle family (Swift, move 129). Twelve previously
missing families remain. The host uses floating-point transforms rather than
RSP fixed-point matrix quantization; pixel-identical rendering is not claimed.

## Shared radial ribbons (families 4, 6, 21)

The native mode-2 Radial20 kernel now drives primary Bind (20), Wrap (35),
Constrict (132), String Shot (81), Spider Web (169), and Disable (50).
It preserves the ten-slot pool, twenty delayed nodes per slot, live source
attachment while nodes wait, family-specific randomized velocities and colors,
gravity, X deceleration, ground clamp, seven-tick spawn cadence and slot expiry.
These are the primary moving ribbons; the already-supported alternate ribbon
routes remain separate.

The ROM oracle executes 84156CCC/84157398/8415782C and 8415DAE4, comparing
every live node and RNG state across both directions and two model scales.
Only actor inputs, scale, RNG, sine and unused auxiliary update are hooked.
The 84187538 display list confirms the shared IA8 texture, 8x16 dimensions,
combiner and geometry flags. Fixed pool meshes are uploaded once per simulation
tick and disposed on native expiry. Existing cached ribbon assets are normalized
to a complete texture descriptor by the player, so no model reimport is needed.

Headless tests run all six primary routes from both sides through the actual
visual viewer wrapper with its named-coordinate scene format, exercising
texture ownership, material state, mesh reuse and cleanup. Full native-FX
parity is still incomplete: nine previously missing lifecycle families remain.

## Shared needle projectile (family 17)

Poison Sting (40), Twineedle (41), and Pin Missile (42) now run the native
projectile lifecycle through the player and visual viewer. The implementation
preserves fifteen history nodes, guRandom consumption, X acceleration and cap,
radius growth, ground-clamped shade ribbon, forty-tick slot life and the
wrapper's separate fifty-tick expiry. Species 13 (Weedle) uses the native
half-size head/radius branch. 84109B88 and 84109BA4 are empty US functions;
they require no substitute audio or geometry.

The catalog decodes the actual 84188A70 display list's eighteen vertices,
sixteen triangles and 4x4 I4 texture from the cached ROM overlay. Head rotation
also rotates its ROM normals; the generic persistent mesh path now supports
lit layers and texture-free shade layers. No reimport is required.

The independent ROM oracle executes initialization, update, and draw including
the ROM's libultra matrix/trigonometric routines. It compares every node exactly,
all trail vertices and colors exactly, and head positions within .02 native
units of the RSP fixed-point matrices. Both directions, below-ground origins,
Weedle and standard scales, and expiry are covered. Viewer tests exercise all
three move routes from both sides, mesh updates/reuse, and disposal.

This completes one more lifecycle family: eight previously missing families
remain (3, 7, 8, 12, 13, 15, 16, 20). Companion common particles can still report
unsupported color-controller/lifetime diagnostics. Host lighting and floating
point transforms do not constitute pixel-identical native rendering.

## Sonic Boom and Surf corrections

The initial family-12 reconstruction used an unrelated strip builder and
continuous four-stream emission. US 841580C8 instead emits on ticks 1, 2, 3,
updates the pool from tick 2, and terminates at tick 50. The replacement has
three 40-tick projectiles, fifteen history nodes each, model scale times .75,
sixteen RNG draws per emission, native return acceleration and Y/Z attraction,
the ROM quad at 84187A78, and texture export 37. The geometry shares the
verified needle ribbon builder with explicit Sonic Boom pitch, scale and alpha.
Source centers are resolved separately from bone attachment endpoints.

Surf now receives the cached fragment image and preserves the native update
return (including termination). Surface positions wrap to signed Vtx shorts;
the previous tick's alpha is captured before the native alpha writer runs.
Geometry is captured once per 30 Hz tick, making redraws side-effect free.
Placement is arena-wide instead of translated to the attacking actor.

The previously missing camera cover is also executed from 8415ADE0, with live
camera eye/focus/projection mapped to the native camera contract. Fixed-point
quad scaling and the primitive-only blue translucent material are preserved.
The cover's unused texture uploads are omitted because neither combiner cycle
consumes them. Missing camera data produces an explicit diagnostic; it does not
prevent the independently valid surface from rendering. Math helper hooks
implement float32 normalize/cross/scale and host sine/cosine; the unused height
query slope-angle output is stubbed, but its height calculation is native.

ROM tests compare Sonic Boom's full pool state, RNG, strip vertices/colors and
head transforms on both sides at two scales. Surf tests independently execute
the native camera math and draw, comparing all 256 surface vertices, UVs,
delayed alpha, camera-cover visibility/positions, finish signal and expiry.
Both move IDs (49 and 57) pass the actual viewer wrapper with both sides,
texture ownership, persistent mesh reuse and disposal. Full worker checks pass.
Host floating-point trig/transform differences mean pixel-identical rendering
is not claimed. Six previously missing families remain: 3, 8, 13, 15, 16, 20.

## Tri Attack (family 20)

The next family uses 84158768 / Radial20 mode 5, not the existing mode-2
radial ribbons. Its isolated persistent kernel executes the US constructor,
pool update, random child spawning and draw-list generation. It emits once,
uses 20 delayed nodes, grows their radius from 2 to 20, and retires the pool
at tick 61 (the wrapper's tick-181 limit is only an upper bound).

Generated vertex/color data and triangles are captured once per 30 Hz tick.
Front-cull, back-cull and cap passes stay separate; the renderer preserves
culling for this geometry. The auxiliary 20-slot spark pool uses the actual
ROM IA8 quad texture, camera-facing transforms and native sine scale envelope.
Draw-side RNG advances once per simulation tick, never on repeated host draws.
ROM tests compare all nodes, vertex/color data, child state, RNG and expiry
on both sides; independent libultra execution checks billboard positions to
0.005 native units and tube vertices within one quantized vertex unit.
The actual viewer wrapper verifies texture ownership, culling, mesh reuse and
disposal. Host trig/fixed-matrix rounding still prevents a pixel-exact claim.

Five previously missing lifecycle families remain: 3, 8, 13, 15 and 16.

## Ice Beam (family 13)

The persistent isolated ROM kernel now executes 84158E24 / 84158E58,
including the shared six-slot, twenty-node textured-stream pool. Native
emission runs every ten ticks; live anchor updates, node delays, scroll,
alpha fade and finish-signal termination remain in the original US code.
84169618 generates forty vertices per active strip once per simulation tick.
The renderer reuses six meshes with native two-cycle selectors, colors,
scroll/shift settings and export-25 I4 textures. Repeated draws do not step
the simulation or consume RNG. This establishes the shared stream kernel
used by family 8, whose separate wrapper is still unimplemented.

Independent full-ROM drawing (including libultra rotation and display-list
submission) checks every pool byte except scratch pointers, all positions
(within one quantized vertex unit), exact UV/color values, RNG consumption,
live anchor changes, repeated emissions and tick-91 termination when signaled
at tick 40. The actual visual-viewer wrapper checks move 58 on both sides,
texture format, persistent mesh reuse, finish propagation and disposal.
Host trigonometric rounding still prevents a pixel-identical claim.

Four previously missing lifecycle families remain: 3, 8, 15 and 16.

## Hyper Beam (family 8)

The native combined wrapper 84159C2C / 84159C6C now drives both its two
beam-core slots and six repeated stream slots. Constructor arguments for
the existing beam simulator are decoded directly from the US 841597AC
calls, including textures, palettes, combiners, scroll/shift and glow.
The stream emitter 84159A50 and shared stream update run in the isolated VM.
Both parts share live anchors and the injected presentation RNG; draw
geometry is captured once per tick and reused by the viewer.

The wrapper returns the beam-core completion result: signaling at tick 40
ends Hyper Beam at tick 72, rather than Ice Beam's tick 91. ROM-backed
tests execute the original combined initializer/update and native draw,
checking the core rings, tube vertices, UVs, materials, stream pool and RNG.
Move 63 is covered by both-side viewer tests for all nine persistent meshes,
ROM texture loading, finish propagation and disposal.

Three previously missing lifecycle families remain: 3, 15 and 16.

## Razor Leaf and Petal Dance (families 3 and 15)

The shared 26-slot stochastic controller now executes the US init/update
wrappers and 84166130/84166270/8416691C directly in an isolated VM.
Family 3 emits texture export 34 and family 15 emits export 35. Each live
slot contributes the ROM's transformed textured quad plus its ten-pair,
vertex-coloured ribbon; all 52 meshes persist across viewer draws. The
native 84166A64 draw generates the quads' fixed matrices and ribbon vertices
once per 30 Hz step. RNG is injected and does not touch battle RNG.

ROM tests independently compare the complete pool except scratch pointers,
RNG consumption, sprite transforms, ribbon vertices/colours, live anchor
changes, saturation at 26 slots and tick-111 finish when signaled at tick 40.
The visual viewer checks moves 75 and 80 on both sides, ROM texture loading,
mesh reuse and disposal.

One previously missing lifecycle family remains: 16.

## Spike Cannon (family 16)

The final lifecycle family now uses the US four-slot projectile pool from
841647D0/84164924/84164C28/84165008. The wrapper emits three shots at
ticks 4, 8 and 12; each shot retains fifteen history nodes and expires after
forty native updates. The viewer draws the ROM needle model at the native
0.09 head scale and persistent cyan trail geometry, with injected RNG and
live source/target anchors. The native update returns zero after its slots
expire, so move completion remains with the battle FX controller.

ROM-backed state and headless viewer checks cover move 131 on both sides.
All nonempty lifecycle families now have built-in callback implementations.
