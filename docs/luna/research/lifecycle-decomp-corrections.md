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
