# Common motion and native color implementation

Evidence: supported US ROM; fragment-79 function index from pret/pokestadiumgs
`c0e10f23d90cc4f335b654711f13e53c2c07323b`. Unmatched functions were checked
against the ROM instructions, not inferred from move names.

Implemented shared paths:

- `8410679C`: geometry angle entries and initial position entries are distinct.
- `84106C78`: directional random samples feed initial position, not velocity.
- `84106D50`: speed modes 1/2 initialize at birth (random or particle-index
  offset). `8410119C` initializes mode 0 at its start age and ramps speed.
- `841013F4`: direction modes 4/5 and 7/8, with paired ROM trig tables.
  Mode 8 replaces the accumulated offset; mode 7 adds to it.
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

The four implemented direction modes occur on 159 primary/alternate move
routes; decoded mode-2 color tracks occur on 104. These counts measure
controller coverage, not complete visual parity. Other directions, curve
controllers, model-relative transforms, special lifetimes, and other native
callback categories still need work. Unsupported paths retain diagnostics.

Common alpha ramp: `84107078` initializes alpha from material+12's first
record; otherwise primary RGBA/geometry alpha or the constructor's 255
applies. `84102534` gates the ramp on age, and `84102598` approaches its
byte target by a byte step. `841025F8` terminates at the target when
descriptor bit 30 is set. The runtime now retains this opacity, submits it
to the renderer, and retires completed particles. The ordinary age-gated
form appears in 179 primary/alternate move routes. Descriptor bit 4 and
flags2 bit 2 require battle/global gate state and remain diagnostic-only.
Fire Punch's first alpha ramp starts at age 8, subtracts 32 per tick,
and reaches zero/terminates at age 15. Color curves and the later alpha
controller branch remain separate work.

The visual viewer consumes the same runtime and background-color conversion
as battles. `J/L`, `K`, `O`, and paused `N` select, replay, switch route, and
single-step. Optional `STADIUM2_VISUAL_FX_TRACE=1` logs geometry and placement.

Acceptance: ROM catalog audit, worker gate, movement/color fixtures, draw
rotation fixture, and viewer replay/background integration. Representative
30-tick runtime smoke checks include moves 7, 8, 9, 52, 53, 55, 57, 58, 59,
85, 87, 94, 123, and 126; positions remain finite. Move 57 has no common
particles in that snapshot and is not counted as visually implemented.
