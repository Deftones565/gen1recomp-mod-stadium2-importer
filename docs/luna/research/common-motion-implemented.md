# Common motion and native color implementation

Evidence: supported US ROM; fragment-79 function index from pret/pokestadiumgs
`c0e10f23d90cc4f335b654711f13e53c2c07323b`. Unmatched functions were checked
against the ROM instructions, not inferred from move names.

Implemented shared paths:

- `8410679C`: geometry angle entries and initial position entries are distinct.
- `84106C78`: directional random samples feed initial position, not velocity,
  even when the optional geometry pointer is NULL. Synthetic fixtures without
  a native emitter retain their injected velocity contract.
- `84106D50`: speed modes 1/2 initialize at birth (random or particle-index
  offset). `8410119C` initializes mode 0 at its start age and ramps speed.
  Its alternative speed-curve branch now samples ROM keyframes at the native
  byte age, interpolates with integer truncation, and applies the constructor's
  sampled percentage before direction movement.
- `84106AC4/84101C00`: the transform scale controller samples a percentage
  once at construction, then replaces the geometry size ramp with ROM
  keyframes at each update. Its scale feeds the same persistent viewer packet.
  The scale curve interpolates with wrapped age; the speed curve uses wrapped
  age for segment selection but the original byte age for interpolation.
- `841013F4`: all direction modes 0..8, with paired ROM trig tables.
  Modes 0..3 rotate forward/back/right/left using live source-object yaw;
  mode 6 uses particle yaw only (811001A0 ignores pitch/roll). Modes 4/5
  are vertical and 7/8 use particle pitch/yaw. Mode 8 replaces the
  accumulated offset; the others add to it. The presentation adapter
  supplies model-matrix yaw, with source-to-target facing for slot-only
  scenes. Missing source orientation remains an explicit diagnostic.
  ROM instruction tests compare all nine modes across six yaws and three
  ticks. Surf's four mode-1 emitters begin at tick 65; viewer acceptance now
  runs through tick 90 on both sides and checks each emitter.
- `84102110`: signed vertical speed ramp; `84106ED4` initializes its random
  percentage. `84102258` then subtracts the authored vertical increment.
- `84102820`: persistent offsets compose into position. `841028DC` copies
  rotation into the rendered object; draw packets now preserve it.
- `84188C7C[2] -> 84107C18 -> 841077E8`: mode 2 constructs a color controller,
  **not** the mode-7 sprite batch at `841076B8`.
- `84100B3C -> 84100710 -> 841005E0`: RGBA track selection/interpolation,
  binary32 operations followed by integer truncation.
- `8410A4F8` writes RGBA at `80128C5C`. `8410A2C8` blends this with an
  RGBA5551 background fill; `8410A444` submits that fill. This affects the
  clear/background color, not an invented full-screen tint over actors.

The nine implemented direction modes occur on 159 primary/alternate move
routes; decoded mode-2 color tracks occur on 104. These counts measure
controller coverage, not complete visual parity. Model-relative transforms,
live gate signals, and other native callback categories still need work.
Unsupported paths retain diagnostics.
The speed-curve branch has 27 distinct ROM records across 112 moves when
counting both dispatch channels; those moves may still depend on other
unfinished components.
The scale-curve branch has 40 distinct ROM records across 128 moves under
the same counting rule.

Common alpha ramp: `84107078` initializes alpha from material+12's first
record; otherwise primary RGBA/geometry alpha or the constructor's 255
applies. `84102534` gates the ramp on age, and `84102598` approaches its
byte target by a byte step. `841025F8` terminates at the target when
descriptor bit 30 is set. The runtime now retains this opacity, submits it
to the renderer, and retires completed particles. The ordinary age-gated
form appears in 179 primary/alternate move routes. The presentation signal
read by `841094EC` now comes from the lifecycle manager, including the host's
per-effect completion event. The viewer's `Y` key can signal that completion
while testing a move. The separate global gate at `841901A4` remains explicit
until its controller is integrated.
Fire Punch's first alpha ramp starts at age 8, subtracts 32 per tick,
and reaches zero/terminates at age 15. Color curves and the later alpha
controller branch remain separate work.

The visual viewer consumes the same runtime and background-color conversion
as battles. `J/L`, `K`, `O`, and paused `N` select, replay, switch route, and
single-step. Optional `STADIUM2_VISUAL_FX_TRACE=1` logs geometry and placement.

Surf material follow-up: `84102338` reads the signed halfword at material+4
as an exact particle-age termination condition when descriptor bit 1 is clear.
All four Surf emitters author age 16. The decoder now retains that field and
motion retires those particles at age 16, while preserving explicit lifetime
overrides. Bit 1's separate hide transition is not treated as termination.
The three colored Surf emitters have a NULL color-animation header:
`84106F34` preloads their constant RGB and `84102370` skips animated updates.
The decoder now distinguishes this supported constant path from opaque color
controllers. ROM execution tests cover all four material records, alpha ramps,
expiry and the hide-vs-termination distinction; the viewer rejects either of
the previously reported lifetime/color warnings.

Acceptance: ROM catalog audit, worker gate, movement/color fixtures, draw
rotation fixture, and viewer replay/background integration. Representative
30-tick runtime smoke checks include moves 7, 8, 9, 52, 53, 55, 57, 58, 59,
85, 87, 94, 123, and 126; positions remain finite. Move 57 has no common
particles in that snapshot and is not counted as visually implemented.
# Native transform axis tracks

`func_84101D54` reads the motion block's `+4` as three angle tracks
(`func_84101888`) and `+8` as three float-position tracks
(`func_84101A08`). The ROM decoder now retains each 12-byte track, and the
30 Hz motion step applies the authored start/end ages, target, and step.
`func_841065E0` initializes the three retail position tracks from their
centered ROM random bound and the battler's dispatch scale byte. A missing
model scale remains diagnostic.

The frame-rule value written to object `+0x81` is a hold countdown, not an
animation-frame index. `func_841054D4` decrements it and suppresses byte-age
advancement until the tick after it reaches zero. The common release predicate
is the proven age-255 endpoint; descriptor bit 28 instead uses the assembled
final Y (`object+0x24 <= 0`). The player resolves that Y through the same
attachment placement used for draw packets. Five retail angle tracks with
nonzero random starts use fragment-27 helpers `81100120/144/168` through the
isolated battle-FX RNG.

`841063D8` mode 4 now samples three signed angle offsets at particle index
zero and reuses that vector for siblings. The next burst resamples in ROM
order. This path occurs on five primary-channel moves and uses the isolated
battle-FX RNG.
