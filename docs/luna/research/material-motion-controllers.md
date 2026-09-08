# Fragment-79 material and motion controller audit

This note is a ROM-backed disassembly report for the supported Stadium 2 US
ROM (`1561c75d11cedf356a8ddb1a4a5f9d5d`).  The fragment-79 overlay is copied
from ROM `0x36F890` to VRAM `0x84100000`; the instruction ranges below are
VRAM addresses.  The report is deliberately conservative: a field whose
consumer or arithmetic crosses an unresolved external function is listed as
unresolved rather than being turned into a renderer formula.

## Function map and structure offsets

The decoder's pointer names can be tied to these exact instruction ranges:

| VRAM range | Observed role | Evidence |
| --- | --- | --- |
| `0x84105E9C..0x84105F0C` | scalar bounded/random helper | `a1==0` returns zero; `a1==-1` becomes `0x10000`; `a0==0` calls external `0x81100094`, otherwise external `0x811000F8`; result is reduced to signed 16 bits at `0x84105EE4..0x84105EFC` |
| `0x84105FC8..0x841063D4` | floating three-vector initializer | modes 0/1 call the scalar helper three times; modes 2/3 use the two external trig tables; mode 5 uses one table pair and leaves Z zero |
| `0x841063D8..0x8410653C` | signed three-vector addition | modes 0/1 add three scalar-helper results to the destination halfwords; mode 4 optionally samples a global vector and adds it |
| `0x84106540..0x841065DC` | selector jump table | selectors 1..6 dispatch through the table at `0x84198C50`; exact index rules are below |
| `0x841065E0..0x84106688` | scalar controller evaluator | reads controller mode at `controller+0`, bound/value at `controller+12`, and adds a converted halfword times the caller float to the destination |
| `0x8410679C..0x84106AC0` | common geometry descriptor | reads root geometry pointer at root `+0x0C`; selector `+0`, scale `+0x04`, position `+0x08`, velocity `+0x0C`, attribute `+0x10` |
| `0x84106AC4..0x84106F30` | common transform/controller descriptor | reads root transform pointer at root `+0x10`; frame/rotation/scale/motion pointers are offsets `+0/+4/+8/+12` of that block |
| `0x84106F34..0x8410716C` | material/color preload | reads root material pointer at root `+0x14`; shape/material pointers and RGBA bytes are copied into the particle object |
| `0x84107170..0x841072B8` | particle object initialization | copies authored root fields and sets object flags; this is not a lifetime update loop |

The common emitter descriptor is 24 bytes: scheduler bytes at `+0x00..+0x03`,
flags at `+0x04`, flags2 at `+0x08`, and geometry/transform/material pointers
at `+0x0C/+0x10/+0x14`.  The geometry block at the decoded geometry pointer
has selector halfword `+0x00` and scale/position/velocity/attribute pointers at
`+0x04/+0x08/+0x0C/+0x10`.
The scale table entries are eight bytes: signed scale at `+0x00` and signed
lifetime byte/halfword source at `+0x06`; `0x8410679C..0x84106830` converts
the scale by the ROM float at `0x84188C68`, which is `0.001f`.

The transform block has four pointers at `+0x00`, `+0x04`, `+0x08`, and
`+0x0C`, corresponding to frame, rotation, scale, and motion.  The rotation
block uses `+0x04` for rotation-offset data and `+0x08` for directional data.
The decoder's `frameRule`, `rotationOffset`, `directionalVelocity`,
`scaleController`, `motionController`, and `motionAxes` names are therefore
structurally correct, but their runtime arithmetic is not all in one function.

Material records are read from root `+0x14`.  `material+0` and `material+2`
are the primary and secondary shape IDs retained by the decoder.  `material+8`
is a color-controller pointer; its `+4` and `+8` pointers provide primary and
secondary RGBA bytes.  `material+12` is a color table pointer whose `+0`
pointer provides constant RGBA bytes.  `0x84106F70..0x84106FB8` copies the
primary color to particle offsets `+0x70..+0x73` and the secondary color to
`+0x8B..+0x8E`.  `0x84107078..0x841070C0` copies constant color to
`+0x87..+0x8A`.

## Exact random-vector behavior

The old preview's centered-range and random-sign formulas are not valid.  The
ROM proves the following instead:

* `0x84105E9C..0x84105F0C` has two variants selected by `a0`: variant 0 calls
  `0x81100094`; variant 1 calls `0x811000F8`.  The external call semantics
  are not present in this overlay, so the bounded distribution and RNG state
  must be supplied by a resolver.  Zero bound returns zero and `-1` is
  normalized to `65536`.
* `0x84105FC8..0x8410603C` (mode 0) calls variant 0 for each of the three
  signed halfword inputs at stack `+0x28/+0x2A/+0x2C`, converts each result to
  float, and writes X/Y/Z at destination `+0/+4/+8`.
* `0x84106040..0x84106094` (mode 1) is identical except it calls variant 1.
  No centering, normalization, or scale multiplication occurs in this range.
* `0x84106098..0x841061E4` (mode 2) calls external variant 0 once with bound
  stack `+0x28`, adds the second halfword at `+0x2A`, converts to float, then
  uses the signed angle fields at context `+0x6A/+0x6C/+0x6E` (each shifted
  right four) to index tables at `0x80087E50` and `0x80098E50`.  The output is
  a table-product combination multiplied by that converted random angle;
  the instruction-level products are retained in the range cited above.
* `0x841061E8..0x84106334` (mode 3) repeats the same external random and
  table-product structure with a different permutation/sign arrangement.
* `0x84106338..0x841063C4` (mode 5) calls variant 0 once, uses the same
  context angle fields and table families, writes X and Y products, and
  explicitly writes `0.0f` to Z at `0x841063B4`.

`0x841063D8..0x8410649C` proves mode 0/1 signed-vector addition: each scalar
  result is added to the existing destination halfword in order X, Y, Z.
Mode 4 at `0x841064A0..0x8410652C` samples a global vector only when the
  caller halfword at stack `+0x32` is zero, then adds the three sampled
  halfwords.  The exact global RNG ownership is outside fragment 79.

Required resolver shape:

```lua
randomScalar = function(variant, bound, context) -> signed16
randomVector = function(mode, values, context) -> {x, y, z}
```

The resolver must receive the variant (`0` or `1`), original bounds, context
angle fields, and an injected RNG stream.  It must not call the host battle RNG.

## Selector, frame, and lifetime findings

`0x84106540..0x841065DC` selects through a six-entry jump table.  With the
decoded arguments used by `0x8410679C`:

* selector 1 returns zero;
* selectors 2 and 5 compute
  `signed16((signed_byte(a0+6) * unsigned_byte(a1+3)) + a3)`;
* selectors 3 and 4 return `a3` unchanged;
* selector 6 returns `signed_byte(a0+6)`;
* out-of-range selectors return zero.

This is not equivalent to the current generation/particle selector shortcut;
the implementation should expose the raw selector inputs and use a ROM-backed
fixture before changing `Native.selectorIndex`.

Frame selection is exact in `0x84106AF8..0x84106BBC`, where the frame mode is
the signed halfword at frame block `+0` and its value is at `+2`.  The output
frame byte is particle offset `+0x81`:

* mode 1: `value * a3 + 1`;
* mode 2: `(a3 % value) + 1` (zero divisor reaches a native break);
* mode 3: external `0x81100094(value)`;
* other modes: the value itself.

`0x841067E0..0x84106830` stores the selected scale-table entry's lifetime at
particle `+0x80`; no expiry comparison occurs in the audited initialization
range.  The actual update/destruction owner and whether `+0x80` is signed,
unsigned, or frame-count inclusive require a caller/update disassembly audit.
An unresolved lifetime must remain nil and be reported as
`unsupported-lifetime`.

## Motion, axes, scale, and color controller findings

`0x84106BC0..0x84106C80` calls `0x841063D8` for the rotation block's first
controller and calls `0x84105FC8` for its second vector controller.  This
establishes initialization order (rotation-vector path first, float-vector
path second), but not per-frame update order.

`0x84106C8C..0x84106CD8` reads an additional controller value and uses external
variant 1 or a default `1000`; `0x84106CEC..0x84106E34` reads motion mode
records.  Mode 1 uses ROM constants at `0x84188C6C` and `0x84188C70` (both
`0.01f`) with an external random sample; mode 2 uses `0x84188C74` (`0.01f`)
and a frame-scaled term.  The destination is particle float offset `+0x5C`.
These are controller-initialization values, not proof of the later update
integration order.

`0x84106E38..0x84106EBC` invokes `0x841065E0` three times for scale-axis
controllers, writing destination floats at `+0x44`, `+0x48`, and `+0x4C`.
`0x841065E0..0x84106674` adds `(controller halfword + sampled halfword) *
caller scale` to each destination.  The controller mode and random-bound
semantics are exact only for the instruction path shown; unresolved pointers
must remain diagnostics.

No audited instruction range establishes a per-frame Euler step such as
`position += velocity * dt`, velocity-before-position ordering, damping, or
scale-controller interpolation.  Those operations must be implemented behind
an explicit resolver until the owner update routine is disassembled.

`0x84106F34..0x8410716C` only preloads material bytes.  It does not interpolate
RGBA, select a secondary shape, or animate a texture.  The color-controller
and constant-color pointers therefore need an update/draw-owner audit before
any interpolation formula is accepted.  `material+2` is copied as authored
secondary shape ID but no use site was proven in this range.

## ROM-wide pointer/family counts

Counts below were generated by traversing both dispatch channels for all 251
moves, deduplicating pointer values within the reachable common-emitter graph.
There are 1,135 common-emitter references and 716 unique emitter descriptors.
The three decoded common descriptor modes occur as mode 0: 274, mode 1: 789,
and mode 7: 72 references.  Unique pointer counts are:

| Family | Unique pointers | References with decoded/non-nil data |
| --- | ---: | ---: |
| geometry blocks | 333 | 894 |
| transform blocks | 214 | 790 |
| material blocks | 517 | 1,134 |
| geometry velocity tables | 177 | 548 |
| frame blocks | 26 | 55 |
| rotation blocks | 176 | 545 |
| rotation-offset specs | 139 | 457 |
| directional-velocity specs | 116 | 237 |
| scale-controller blocks | 40 | 171 |
| motion-controller blocks | 161 | 481 |
| motion-axis blocks | 2 | 10 |
| color-controller blocks | 133 | 355 |
| color-table blocks | 216 | 525 |
| secondary shape IDs | 131 | 223 |
| constant-color pointers | 75 | 78 |

The internal function families are single audited roots (`0x84105FC8`,
`0x841063D8`, `0x841065E0`, `0x8410679C`, `0x84106AC4`, and
`0x84106F34`), plus the two unresolved external scalar RNG targets and the
six selector jump targets.  Pointer multiplicity must not be mistaken for six
different native algorithms; the same root evaluates many data records.

## Recommended ROM-backed golden fixtures and APIs

1. Fire Punch move 7, program 259, shape 47: preserve the decoded rotation
   offset mode 0, directional mode 2, geometry scale `0.3`, lifetime `1`, and
   exact pointers `0x8417B624`, `0x8417B650`, and the material shape 47.  A
   golden should record resolver calls and raw output, not invent random values.
2. A reachable mode-2 and mode-3 geometry record: compare the random bound,
   angle offset, shifted context angles, and ordered table addresses before
   accepting vector formulas.
3. A frame-mode 1/2/3 record: assert output byte `+0x81` and mode-3 external
   RNG call arguments, including the mode-2 zero-divisor diagnostic.
4. A scale-controller record with all three `0x841065E0` call sites: assert
   destination offsets `+0x44/+0x48/+0x4C`, sampled halfwords, and caller
   scale.
5. A material record with primary, secondary, and constant colors: assert
   bytes at `+0x70/+0x8B/+0x87` and explicitly retain unresolved color update
   diagnostics; do not assert interpolation until its update owner is found.
6. A secondary-shape record: assert `material+2` survives resource resolution
   and remains separate from primary `material+0`.

Suggested pure resolver contracts are `Motion.randomScalar`,
`Motion.randomVector`, `Motion.selectIndex`, `Motion.frameRule`,
`Motion.controller`, and `Motion.materialController`.  Each should return a
plain Lua value plus a structured diagnostic on an unresolved pointer or
unknown mode.  Every diagnostic must use
`code,severity,effectId,programId,address,kind,message`; no fallback formula
should be hidden behind a default branch.
