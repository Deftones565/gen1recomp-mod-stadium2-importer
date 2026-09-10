# Shared beam simulation

Implemented in `lib/stadium2_battle_fx_beam.lua`, using the supported US ROM
fragment 79 routines 84166F60, 841670A8 (simulation fields), 841674C0 and
841677C4. Four slots retain ten rings each. Updates track both native endpoint
inputs, clamp endpoint B's Y to 200, grow the tapered radius profile, rotate
rings and run the controller-triggered finish window. Float operations round
to binary32; ages and finish thresholds retain signed 16-bit storage.

The finish transition is checked after incrementing age; manager termination
is checked before incrementing it. A finish signal on the first tick gives
threshold 31, shrinking begins on tick 16, and termination returns on tick 33.
The minimum shrinking radius is 0.10000000149011612 at ROM address 8418C914.
The simulation consumes no RNG and snapshots do not alias mutable state.

Families 0, 5 and 18 now dispatch their init/update callbacks to this kernel.
Their setups at 84158F00, 84158914 and 84159584 create two, two and one active
slots respectively. Each setup uses growth duration 20, radius increment 5,
velocity multiplied by 10 then 1.2000000476837158, and no rotation increment.
The per-layer initial/max radii, texture export indices, scroll/shift fields,
both combiner cycles, primitive/environment/overlay colors and LOD fraction
are retained. The 8-word records are combiner selectors, not tile descriptors.

The manager accepts `resolveBeam(context, instance)` or `context.lifecycleBeam`
with setup `origin`/`direction` (841569E0 outputs) and live `endpointA`/`endpointB`
(84109780/841098FC outputs). Missing inputs diagnose `unresolved-beam-endpoints`;
they do not create origin-centered substitutes. Automatic model-joint resolution
in the battle adapter/viewer remains outstanding. The shared player now accepts
`resolveBeam(context, sceneContext)` and the battle adapter/viewer provide host
model centers as an explicitly diagnosed fallback. An injected phase resolver
still overrides builtins. A delayed valid endpoint resolver initializes state
when it becomes available.

Resources.beamTexture resolves indexed 32x32 I4 images through move resource
exports. Cached RGBA keeps alpha opaque, following the renderer's existing I
texture contract; native intensity-alpha restoration belongs to the material.

Draw now emits tube/glow geometry to the shared player. Moves 60, 62 and 76
reach the renderer in the battle adapter and visual viewer. The verified
84168000 tube has 90 vertices, 144 triangles and dual scrolling I4 textures.
The host draws both face orientations without culling rather than reproducing
the native two opposite-culling submissions. The 84163380 glow uses the ROM's
ten-vertex strip, 32x32 IA8 texture at 84188738, one-cycle combiner and disabled
depth. Its width follows the normalized cross product of beam and camera vectors.
Each layer keeps a mesh across frames; same-frame draws do not advance state.
Expired lifecycle meshes are released.

Native draw-time scroll and phase-two alpha are advanced once per simulation
tick at 30 Hz. Glow uses the previous alpha factor, matching native call order.
This does not yet model the separate abrupt-finish flag from 841094E0 or pause
flag from 800711B0. Automatic host finish signaling is now wired: Gen 1 signals
on animPlaying's falling edge; Gen 2 observes runner completion/removal/replacement
and handles retained final frames and moves without animation runners. Requests
are scoped by effect ID, including delayed lifecycle spawns, so new moves do not
inherit another move's finish flag. This maps host animation completion to the
native lifecycle signal; it does not claim matching Stadium battle-controller
timing. Unsignalled viewer beams continue until stopped. Native angle/matrix quantization and
ROM frame-by-frame visual comparison are not yet validated. Full parity is not
claimed; model-joint placement is explicitly approximate.

Validation: `tests/stadium2_battle_fx_beam_test.lua` exercises slot capacity,
endpoint interpolation/clamping, taper caps, live endpoint changes, snapshot
isolation, held finish signals, termination boundaries and signed age wrapping.
It also checks all three lifecycle setups/updates, moving resolver endpoints,
missing endpoint and unsupported draw diagnostics, five layers' combiner words
against the ROM, and every decoded texture pixel against its resource export.
Headless real-renderer construction additionally covers all three primary move
routes, tube/glow material state, mesh reuse/update and cleanup. No images or
GUI inspection were used. ROM-backed worker checks and renderer tests pass.

## Joint metadata audit

84114730 copies selected animation-dispatch row byte2 into battler+61C.
8411E21C returns that byte for the source query. Target helper8411E22C returns
dispatch+13DA, which is context254 (hit) byte2. animation_dispatch.decodeRecord
now retains fxJoint and the raw20byte row instead of discarding these inputs.
8003C9B8 searches a saved attachment list by selector; it is not a skeleton
array index. Graph attachment extraction, pack persistence and animated marker
lookup are now implemented. Renderer:attachmentPosition(label) returns an isolated
position from the current posed transform. The battle adapter uses these for
source xyz and target x/z when the imported dispatch and marker are available.
Native target-height and shadow-marker handling are now implemented as described
below. Packs missing the new profile retain an explicitly approximate fallback.
The attachment marker is graph command0x24: command table80094BB4 entry36
selects80040D50, which reads signed16(command+2) and calls80038BF8 to create
type0x1B node with label at+18. Renderer table80094924 entry27 selects8003C344;
it registers current matrix translation under that label via8003C2D8 (up to12
entries). fragment.lua retains0x24 labels and their current transform. An optional
FXAT trailer in the existing render metadata preserves those records and raw
dispatch rows in normal/shiny packs. Cache format S2IMP56 requires reimporting
older model caches to obtain them. Legacy pack readers remain supported.
The additional native offsets are signed bytes from row+C/D/E, rotated by
battler orientation before addition. Both endpoints now receive these offsets,
including missing-marker fallbacks. Target offsets follow the current dispatch
row, independently of the fixed context254 marker selector.

ROM-backed acceptance now extracts both viewer models: Koffing109 and
Croconaw159 use graph label7 for moves60/62/76, and graph label9 for hit
context254. The test checks those actual extracted markers, in addition to
synthetic graph-stack, normal/shiny pack, animated transform and adapter tests.

## Native height and shadow marker audit

84113014 loads the species profile from ROM 49DA60 + (species-1)*30 (hex).
The source base is 49B780: the signed addiu after lui 004A is -4880.
84112704 copies profile+14 to battler+638/+648 and profile+08 to +650.
8411E1BC returns +648 minus +650, with binary32 rounding. The raw 48-byte
profile is preserved by the optional FXBP render-metadata trailer. Koffing's
values are 68.5 and 65 (height adjustment 3.5); Croconaw's are 26.5 and 0.
Neither value is inferred from the exported mesh bounds.

841098FC always replaces target marker Y with actor Y plus this height, then
applies offsets. Controller flag4 sets Z to zero and caps Y at30, followed by
the unconditional 0..200 clamp. Missing source markers use 8411DCCC: profile
center Y normally, center+200 for flag2, or zero for flag4 (flag2 takes priority).
Source offsets apply afterward and source Y is not clamped. The pure endpoint
module accepts those native controller flags; the host adapter accepts explicit
actor.nativeFxFlags and defaults to zero. Mapping host Fly/Dig battle state to
those flags is not supplied by this endpoint change.

Graph command18 calls 800404AC -> 8003854C, constructing type0F. Renderer
8003C390 registers marker100 at the current matrix before checking shadows.
Extraction now retains this marker, including a root transform with bone=-1.
There is no invented marker101 fallback: an unregistered label follows the
native missing-marker rule. Both viewer species now expose their authored
shadow marker100. Ordinary labels retain first-match lookup and capacity12.

The adapter maps these inputs through the host's existing model matrices and
actor slots, including host scale conversion. Host arena floor placement and
orientation remain host conventions; this does not establish bit-exact native
matrix quantization or Stadium controller timing. Tests cover all 279 profiles,
signed rotated current-context offsets, missing markers, flag priority/clamps,
root shadows, and normal/shiny pack round trips. No GUI images were inspected.
