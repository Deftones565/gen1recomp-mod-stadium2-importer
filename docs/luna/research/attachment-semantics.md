# Common-particle attachment and placement semantics

## Scope and provenance

This report is a ROM-only trace of the common-particle path in fragment 79 of
the supported `Pokemon Stadium 2 (USA).z64`.  The overlay was extracted from
ROM `0x36F890..0x419480` and loaded at VRAM `0x84100000`; all addresses below
are VRAM addresses.  The trace covers the common descriptor used by emitter
modes 0, 1, and 7, not the resolved native-object pointer used by modes 2, 4,
5, 6, and 8.

The disassembly was produced with:

```sh
dd if='Pokemon Stadium 2 (USA).z64' of=/tmp/stadium2_fragment79.bin \
  bs=1 skip=$((0x36F890)) count=$((0x419480-0x36F890)) status=none
mips-linux-gnu-objdump -D -b binary -m mips:isa32 -EB \
  --adjust-vma=0x84100000 /tmp/stadium2_fragment79.bin
```

No semantic names are assigned to external callbacks unless the local
instructions prove their inputs and outputs.  In particular, a callback that
looks like an actor, camera, or ground query is reported as an unresolved
external operation rather than being replaced by a guessed battle anchor.

## Result in one paragraph

The current decoder's high-bit attachment categories are not supported by the
common-particle placement code.  The common descriptor is a 24-byte object:
the scheduler header is `+0..+3`, flags are `+4`, the word at `+8` is copied
from ROM but has no direct consumer in the traced common constructor,
geometry is `+0x0c`, transform is `+0x10`, and material is `+0x14`.
`func_841072BC` reads only `root+4` for the common placement decisions.  It
selects scale and an offset callback, initializes geometry/transform/material,
then either calls `func_84104A00` (anchor construction) or
`func_8410668C` (saved-origin search).  `func_84104D28` then emits a visual
position by adding four three-component vectors in a fixed order.  The ROM
proves the arithmetic and masks, but not the external callback coordinate
frames; those must remain explicit resolver inputs.

## Common descriptor and call order

For modes 0, 1, and 7, `func_841072BC` receives an event wrapper at `a0` and
loads the common descriptor root with `lw s4,0(a0)` at `0x841072EC`.
The descriptor fields consumed by this path are:

| descriptor offset | proven use |
| ---: | --- |
| `+0..+3` | scheduler start, interval, repeat count, common-particle count |
| `+4` | common flags; tested directly and passed to the anchor/placement helpers |
| `+8` | retained by the decoder as `flags2`; no direct load of `root+8` was found in the common constructor, anchor setup, placement sum, geometry, transform, or material calls |
| `+0x0c` | geometry pointer, loaded by `func_8410679C` at `0x841067C0` |
| `+0x10` | transform pointer, loaded by `func_84106ADC` |
| `+0x14` | material pointer, loaded by `func_84106F44` and later by `func_84107588` |

The per-particle object allocated at `0x8410731C` has these fields relevant to
placement:

| particle offset | proven use in fragment 79 |
| ---: | --- |
| `+0x08` | external actor/model/context pointer passed to callbacks |
| `+0x0c` | visual-side link/state pointer used by material setup |
| `+0x10` | common descriptor root used by `func_84104A00` |
| `+0x18` | common scale written by the emitter and material initializer |
| `+0x1c` | geometry scalar written by `func_8410679C` |
| `+0x2c,+0x30,+0x34` | authored/common offset vector; also cleared by saved-origin handling |
| `+0x38,+0x3c,+0x40` | anchor/origin vector assembled by `func_84104A00` |
| `+0x44,+0x48,+0x4c` | transform/controller vector |
| `+0x50,+0x54,+0x58` | additional motion/controller vector |

The common constructor's order is fixed by `0x84107548..0x84107584`:

1. `func_8410679C` initializes geometry.
2. `func_84106AC4` initializes transform/controller data.
3. The scale at particle `+0x1c` is multiplied by the emitter scale and stored
   at particle `+0x18`.
4. `func_84106F34` initializes material state.
5. Material shape and descriptor flags decide whether `func_84104D28` creates
   the visual object (`0x841075A4..0x841075E4`).
6. The object flags are updated; if bit `0x80` is set, `func_84104A00` is
   called at `0x84107640..0x84107664`, otherwise `func_8410668C` is called at
   `0x8410766C..0x84107670`.

This is initialization order.  It does not establish a later per-frame camera
or battler reattachment policy.

## Exact common-flag consumers

The following are consumers of the common descriptor word at `root+4`.
`0x81100054` is an external bit-test helper; `0x81100074` is a second
external flag/query helper.  Their implementation is outside fragment 79.

### Scale and initial offset selection (`0x84107368..0x84107544`)

`func_841072BC` loads `root+4` at `0x84107368`.

* `0x80` at `0x8410736C..0x84107380` forces initial `f20 = 1.0`.
* Without `0x80`, bit `0x8` at `0x84107374..0x84107384` selects an external
  scale query.  `0x8411E358(global+0x194, event+0x0A)` returns a signed
  integer, which is converted to float, multiplied by the global scalar at
  `0x84198C78`, and stored in `f20` (`0x8410738C..0x841073B8`).
* Without either path, `0x8411EE54(global+0x194)` supplies the signed scale
  (`0x841073C0..0x841073E8`).  The coordinate/unit meaning of both external
  scale values is unresolved.

The code then tests a composite mask `0x800020` at `0x841073F0..0x841073FC`.
If that query is true, it tests `0x8` again at `0x84107404..0x84107410`:

* With bit `0x8`, callbacks `0x8411EE5C`, `0x8411EE64`, and `0x8411EE6C`
  (all passed `global+0x194`) return signed byte components.  They are
  converted to floats, packed with a 16-bit value read from the global record,
  and passed to `0x811001A0` at `0x84107510`.  The returned vector is added to
  particle `+0x2c,+0x30,+0x34` at `0x84107518..0x84107544`.
* Without bit `0x8`, callbacks `0x8411E46C`, `0x8411E580`, and `0x8411ED40`
  receive `(global+0x194, event+0x0A)` and produce the same three-component
  offset, which is passed through `0x811001A0` and added at the same range.

The external functions do not expose names or coordinate conventions in the
overlay.  This proves an offset vector and its addition order, not “camera
line”, “side lane”, or “battler origin”.

### Anchor setup (`func_84104A00`, `0x84104A00..0x84104D24`)

The helper receives the particle object, loads its descriptor root from
particle `+0x10` at `0x84104A0C`, and tests the word at root `+4` through the
saved pointer `root+4` (`0x84104AA8..0x84104AB0`).  The branch order is:

1. If an earlier nested transform graph is present, the helper reads a
   three-component vector from the global table at `0x8419C958` with a 12-byte
   stride and writes it to particle `+0x38,+0x3c,+0x40` (`0x84104A20..0x84104AA0`).
   The selector is a nested shape/model value.  Its actor/model meaning is
   unresolved.
2. Otherwise, flag `0x100` at `0x84104AAC..0x84104AD4` writes zero to all
   three anchor components and branches to the actor-table tail.
3. Else flag `0x400` at `0x84104ADC..0x84104B1C` calls
   `0x8411E1D4(particle+8)`, converts the signed result, multiplies it by the
   literal `0xC3160000` (`-150.0f`), writes the result to anchor X, and zeros
   anchor Y/Z.  This is lane-like arithmetic, but the callback's semantic
   identity is unresolved.
4. Else flag `0x10` at `0x84104B20..0x84104B84` calls
   `0x8411DCCC(particle+8, particle+0x38)` for the anchor vector.  If flag
   `0x4` is set (`0x84104B4C..0x84104B64`), anchor Y is forced to zero;
   otherwise flag `0x8` (`0x84104B68..0x84104B84`) permits
   `0x8411EF90(particle+8)` to supply Y.
5. Else flag `0x20` at `0x84104B88..0x84104C10` chooses a model/actor callback:
   `0x8003C9B8(particle+8, signed particle byte +0x7e)` is attempted first,
   with `0x8411DCCC` as fallback.  The same `0x4`/`0x8` Y override sequence
   follows at `0x84104BDC..0x84104C10`.
6. The actor-table tail calls `0x8411E1F8(particle+8)`, indexes global table
   `0x84193DD0` by `index*16`, and requires table halfword `+0x12` bit `0x4`
   (`0x84104C14..0x84104C34`).  Under its additional descriptor tests, it can
   copy actor data at `+0x24` into anchor X, call `0x8411E1BC` using actor data
   at `+0x2c` for Z, add literal `30.0f` to actor Y, and clamp Y to `30.0f`
   (`0x84104C64..0x84104CAC`).  Exact actor structure semantics remain
   external/unresolved.
7. A later descriptor flag `0x20` test at `0x84104CCC..0x84104D10` clears the
   particle offset vector and copies global `0x84190020` into the anchor.  The
   global vector is therefore a saved-origin candidate, but the producer and
   lifetime policy for that global are unresolved.

The helper always returns after the actor-table tail (`0x84104C14..0x84104D14`)
unless the earlier nested path branched directly to the epilogue.  Thus the
zero/lane/model vectors above may be further affected by the actor-table
conditions; callers must model the branch context, not select one category by
move name.

### Shared-origin updater (`func_8410668C`, `0x8410668C..0x84106798`)

When the emitter's `0x80` test at `0x84107640..0x84107670` is false, the
common path scans 300 entries from global `0x8419C950`, stride `156` bytes
(`0x841066A8..0x84106738`).  It checks each candidate's nested flags and
selects one candidate.  If found, candidate floats at `+0x20,+0x24,+0x28`
are added to the current particle `+0x2c,+0x30,+0x34` at
`0x84106748..0x84106778`.  This proves a saved/common-origin accumulation
operation and its order; it does not prove that the candidate is a battler,
camera, or prior particle.

### Placement sum and visual creation (`func_84104D28`, `0x84104D28..0x84104F38`)

`func_84104D28` allocates a visual with `0x841047AC`, links visual `+0x14`
to the source particle, and stores the reverse link at particle `+0x0c`
(`0x84104D44..0x84104D6C`).  If descriptor flag `0x1` is true at
`0x84104D70..0x84104DB0`, material halfword `+6` is converted and passed to
`0x84105930`; otherwise it calls `func_84104A00` (`0x84104DB8..0x84104DC0`).
This flag is a scale/anchor-preparation switch in this consumer, not a proven
camera-line bit.

The visual world position is the exact component-wise sum below:

```text
visual +0x24 = particle +0x38 + particle +0x2c
              + particle +0x44 + particle +0x50
visual +0x28 = particle +0x3c + particle +0x30
              + particle +0x48 + particle +0x54
visual +0x2c = particle +0x40 + particle +0x34
              + particle +0x4c + particle +0x58
```

The instruction ranges are X `0x84104DC4..0x84104DE4`, Y
`0x84104DE8..0x84104E04`, and Z `0x84104E08..0x84104E24`.  Within each
component the additions occur in the order anchor, common offset, transform,
then motion.  No axis is swapped or negated here.  A descriptor flag query at
`0x84104E28..0x84104E6C` can save anchor+common-offset to global
`0x84190020`; the saved vector is not itself a camera or battler proof.

After the position sum, primary shape/material state is consumed at
`0x84104E70..0x84104EC8`.  A nonzero secondary shape enters a separate path;
descriptor flag `0x4000` is tested at `0x84104EDC..0x84104EF4` before the
secondary visual helper.  These are rendering/material decisions, not anchor
selection.

## Why the current decoder labels must change

The current `attachmentContract` in `lib/stadium2_battle_fx_rom.lua` assigns
attachment categories to high bits (`0x01000000`, `0x04000000`, and
`0x00100000/0x00200000`) and assigns saved origin to `flags2 & 0x20`.  The
common path contradicts those labels:

| current label | current mask | retail common-path evidence |
| --- | ---: | --- |
| `world-origin` | `flags & 0x01000000` | no consumer in the traced attachment path; actual zero-anchor branch is `flags & 0x100` |
| `side-lane` | `flags & 0x04000000` | no consumer; lane-like external scalar path is `flags & 0x400` at `0x84104ADC..0x84104B1C` |
| `battler-origin` | `flags & 0x00100000/0x00200000` | no matching branch; actor/model callbacks are selected by `0x10`, `0x20`, and actor-table conditions |
| `useSavedParticleOrigin` | `flags2 & 0x20` | no direct `root+8` read; descriptor `flags & 0x20` participates in model callback and saved global-origin copy |
| `cameraLine` | `flags & 0x1` | no camera address/load; bit `0x1` affects scale preparation/material birth and must not be named camera-line |
| `oppositeSide` | `flags & 0x8` | bit `0x8` selects scale/offset and optional external Y query; side selection is unresolved |
| `forceGroundY` | `flags & 0x40000` | no matching consumer; proven Y zero override is `flags & 0x4` |
| `useBattlerGroundY` | `flags & 0x80000` | no matching consumer; an external Y callback is gated by `flags & 0x8` |
| `fixedScale` | `flags & 0x80` | partially supported only as initial `f20=1.0` at `0x84107368..0x841073B8`; the same bit also chooses anchor setup vs shared-origin update |

The architect should preserve raw words and replace these categories with a
resolver status such as `unresolved-common-flags` until external callbacks
are mapped.  It is safe to expose the proven low-bit operations above; it is
not safe to reinterpret all of them as world, side, battler, or camera modes.

## Retail coverage and flag combinations

Counts below were obtained by decoding all 395 native programs and all 251
move routes.  “References” counts particle-emitter records, “descriptors”
deduplicates by descriptor address, and “moves” deduplicates move IDs across
primary and alternate routes.  A move count of zero means the descriptor is
present in the 395-program catalog but not reachable from the 251 move table.

| common `flags` bit | references | descriptors | moves | proven consumer |
| ---: | ---: | ---: | ---: | --- |
| `0x00000001` | 48 | 44 | 37 | placement scale preparation / material birth branch |
| `0x00000002` | 7 | 6 | 1 | primary-shape visual policy at `0x841075B4` |
| `0x00000004` | 445 | 353 | 171 | anchor Y zero override |
| `0x00000008` | 135 | 122 | 2 | scale and offset callback family; optional external Y |
| `0x00000010` | 41 | 31 | 31 | anchor callback family |
| `0x00000020` | 133 | 111 | 54 | model/actor callback and saved global-origin branch |
| `0x00000040` | 5 | 5 | 6 | no separate attachment operation isolated |
| `0x00000080` | 101 | 92 | 49 | initial fixed scale and anchor/shared-origin selection |
| `0x00000100` | 1 | 1 | 1 | zero anchor vector |
| `0x00000400` | 94 | 83 | 34 | lane-like external scalar path |
| `0x00004000` | 8 | 8 | 2 | secondary-shape visual path |

The remaining low/high bits occur in descriptors but have no direct load/test
identified in the common placement ranges above; they may be consumed by
geometry, transform, material, or external routines and must remain raw until
those consumers are mapped.

The `flags2` (+8) bit coverage is small and especially important because it
does not imply a placement operation:

| `flags2` bit | descriptors | moves | direct common-path consumer |
| ---: | ---: | ---: | --- |
| `0x01` | 2 | 1 | none found |
| `0x02` | 24 | 0 | none found |
| `0x04` | 2 | 2 | none found |
| `0x08` | 2 | 0 | none found |
| `0x10` | 1 | 0 | none found |
| `0x20` | 1 | 0 | none found |

## Recommended Attachment resolver API

The resolver should accept raw descriptor words and explicit context rather
than pretending the flags are already semantic categories:

```lua
Attachment.resolve({
  flags = emitter.flags,
  flags2 = emitter.flags2,
  descriptor = emitter.descriptor,
}, {
  effectId = effectId,
  programId = programId,
  address = emitter.descriptor,
  particle = {
    context = actorOrModelPointer,
    generation = generation,
    index = particleIndex,
    offset = {x = ..., y = ..., z = ...},
    anchor = {x = ..., y = ..., z = ...},
    transform = {x = ..., y = ..., z = ...},
    motion = {x = ..., y = ..., z = ...},
  },
  anchors = {
    worldOrigin = ...,
    sourceModel = ...,
    targetModel = ...,
    cameraLine = ...,
    savedOrigin = ...,
  },
  resolvers = {
    external = function(address, args) ... end,
    actorTable = function(context) ... end,
    modelOrigin = function(context, generation) ... end,
    groundY = function(context, mode) ... end,
    scale = function(context, event) ... end,
  },
})
```

The result should include `resolved`, `position`, `scale`, `mode=nil` unless a
resolver proves it, and the raw flags/context.  Any missing external callback
or ambiguous branch should emit the frozen diagnostic fields
`code,severity,effectId,programId,address,kind,message`, for example
`unsupported-attachment-external`, and retain the unresolved inputs.  The
resolver must not silently substitute source battler position for a missing
model/camera/actor result.  The placement sum can be implemented independently
and deterministically once the four vectors are supplied.

## ROM-backed golden fixtures

The following fixtures are recommended for the next implementation packet:

1. **Exact placement sum:** synthetic particle fields with distinct values in
   `+0x38/+0x2c/+0x44/+0x50` (and Y/Z equivalents), checking visual offsets
   `+0x24/+0x28/+0x2c` and the anchor, offset, transform, motion order.
2. **Zero-anchor branch:** a descriptor with `flags=0x00000100`, checking
   anchor `{0,0,0}` and that the actor-table tail remains explicit.
3. **Lane callback branch:** a descriptor with `flags=0x00000400`, injecting
   `0x8411E1D4` and checking signed result × `-150.0`, with Y/Z zero.
4. **Y override matrix:** `flags=0x10` and `flags=0x20`, each crossed with
   `0x4` and `0x8`; check callback selection and that Y is either zero or
   supplied by the injected `0x8411EF90` resolver.
5. **Fixed-scale/anchor policy:** `flags=0x80` with and without a saved-origin
   candidate, checking initial scale `1.0` and the `func_84104A00` versus
   `func_8410668C` call policy separately.
6. **Saved-origin global:** `flags=0x20` with an injected `0x84190020` vector,
   checking offset clear followed by anchor copy; test missing global as an
   unsupported diagnostic.
7. **External offset families:** `flags=0x8` and its absence, injecting the
   three callback components and `0x811001A0`, checking the exact addition to
   particle `+0x2c/+0x30/+0x34`.
8. **`flags2` negative control:** use each observed nonzero `flags2` value,
   especially `0x20`, and assert that no placement behavior is inferred until
   a separate consumer is proven.

For retail regression, retain descriptor addresses and raw words for at least
the Fire Punch program 259 common emitters (including the descriptor used by
shape 47), plus one descriptor for each low-bit row above.  The fixture should
compare raw `flags/flags2`, geometry/transform/material pointers, callback
resolver invocations, and final vector arithmetic; it should not compare a
guessed semantic mode string.

## Unresolved behavior

The following remain outside the evidence in this pass: the implementations
of external callbacks `0x8003C9B8`, `0x81100054`, `0x81100074`, `0x811001A0`,
`0x8411DCCC`, `0x8411E1BC`, `0x8411E1D4`,
`0x8411E1F8`, `0x8411E358`, `0x8411E46C`, `0x8411E580`, `0x8411ED40`,
`0x8411EE54`, `0x8411EE5C`, `0x8411EE64`, `0x8411EE6C`, and `0x8411EF90`;
the producer and ownership of globals `0x84190020`, `0x84190194`, and the
actor table at `0x84193DD0`; camera-line and opposite-side selection; model
bone versus actor origin; and any post-initialization attachment updates.
These should be represented as injected resolver contracts and explicit
unsupported diagnostics, not approximated with battle-side or camera values.
