# Fragment-79 common-particle update, expiry, and cleanup audit

This is a ROM-backed trace for the supported Stadium 2 US ROM
(`1561c75d11cedf356a8ddb1a4a5f9d5d`).  Fragment 79 is copied from ROM
`0x36F890` to VRAM `0x84100000`; all addresses below are VRAM addresses.  The
pool is 300 objects, 156 bytes (`0x9c`) each, allocated by
`0x84100134..0x84100170` and addressed through `0x8419C950`.

## Proven per-frame call order

The fragment's per-frame root is `0x841055D8..0x8410562C`:

```text
0x841055E0  jal 0x841054D4   common-particle pre-pass
0x841055E8  jal 0x84105B90   global/current-context update
0x841055F0  jal 0x841052AC
0x841055F8  jal 0x8410545C
0x84105600  jal 0x84107B68   native-object scheduler
0x84105608  jal 0x841029DC   common-particle update/dispatch/free pass
0x84105610  jal 0x841092B8
0x84105618  jal 0x84105CE8
```

`0x841054D4..0x841055D4` walks all 300 active objects.  For an ordinary
object (`flags +0x14 & 0x800 == 0`) it performs:

```text
age = (lbu object+0x7f) + 1
sb  age, object+0x7f
```

The store is a byte store, so the value wraps modulo 256.  This pass happens
before `0x841029DC`, hence the first normal engine tick evaluates the
controller tables at age 1, not age 0.  A particle held by the `0x800` flag
uses the separate countdown byte `+0x81`: the countdown is decremented and
the flag is cleared when it reaches zero, but that same tick does not perform
the `+0x7f` increment.  `+0x81` is therefore not the common-particle age.

`0x841029DC..0x84102B38` walks the same pool and dispatches `lbu object+0x7c`
through the table at `0x84188BB0`:

| category | update called |
| ---: | --- |
| 0 | `0x841027B4`, then `0x8410291C` |
| 1 | `0x841027B4` when object flag `0x800` is set |
| 2 | `0x84100B3C` |
| 3 | no category-specific update |
| 4 | `0x84100B3C` |
| 5 | `0x84100C68` |
| 6 | `0x84100DE4` |
| 7 | `0x841027B4` (when object flag `0x800` is set) |
| 8 | `0x84100B3C` |

Categories 0, 1, and 7 use the common transform path in
`0x841027B4..0x84102918`; that function calls `0x84101D54` before assembling
the output transform.  After the category path returns, the pass always
calls `0x8410009C` and, if it returns nonzero, calls
`0x8410488C` followed by `0x84100350`.

## Age expiry and inclusivity

`0x8410009C..0x84100130` is the common termination predicate.  The helper
functions at `0x84100054` and `0x84100074` test a particle's flag word
(`+0x14`) for a mask present and absent, respectively.  The predicate is
equivalent to this control flow (the `+0x92` check is independent):

```text
done = (lbu object+0x92 == 0)

if lbu object+0x7f == 0xff then
    if (lw object+0x14 & 0x20000) == 0 then
        done = true
    end
end

if (lw object+0x14 & 0x20000) ~= 0 and
   (lwc1 object+0x24 <= 0.0f) then
    done = true
end
```

The byte at `+0x7f` is read at `0x841000B4..0x841000C4`.  The ordinary path
therefore reaches the endpoint when the pre-pass changes age `0xfe` to
`0xff`; the category update has already run using age `0xff`, and the
termination predicate is then evaluated.  This is exact-byte equality, not a
general `>=` comparison.  If the object survives at `0xff` because flag
`0x20000` is set and `+0x24` is positive, the next pre-pass wraps age to zero
and it can continue.  With that flag set, `+0x24 <= 0.0f` can terminate the
object at any age, including before `0xff`.

New objects are initialized with `+0x92 = 1` and `+0x7f = 0` at
`0x84100174..0x8410025C`.  `0x84100094` clears `+0x92`; the release path
uses that helper at `0x84100350..0x841003A8` and also clears the flag word and
active marker `+0x98`.

There is no comparison of the authored scale-entry byte at particle `+0x80`
in this lifetime path.  `0x841067E0..0x84106830` selects a scale entry,
loads its signed halfword at entry `+0x06` (`0x8410680C`), and stores the low
byte with `sb ..., +0x80` at `0x84106814`.  The object initializer only zeros
`+0x80` at `0x841001D8`.  A fragment-wide search of particle accesses finds
the `+0x80` write but no particle `lbu/lb/lh/lhu` consumer; the `+0x80`
accesses in unrelated later functions are different structures.  Thus the
scale-entry `+0x06` value is proven authored data, but it is not proven to be
the native expiry owner and must not be used as an automatic lifetime by
itself.

## Common transform and motion ordering

`0x84101D54..0x8410274C` consumes the post-pre-pass age.  Proven age-indexed
operations include:

* the geometry/velocity record selected through `root +0x0c`, particle
  selector `+0x7d`, and age `+0x7f` (`0x84101DD0..0x84101EAC`);
* rotation controllers writing `+0x6a/+0x6c/+0x6e` through
  `0x84101888` (`0x84101F7C..0x84101FE8`);
* scale-axis controllers writing `+0x44/+0x48/+0x4c` through
  `0x84101A08` (`0x84101FEC..0x84102044`);
* an angle/controller evaluation at `0x84102048..0x841020C8`, including
  `0x84101084` and external `0x811001A0`, which produces the motion-related
  vector fields at `+0x50/+0x54/+0x58`.

The scalar helper `0x84101AF4..0x84101BFC` is also called from the common
path.  It starts with factor `1.0`, optionally obtains an external random
value (`0x8411E358` or `0x8411EE54`) under particle flag `0x2000`, then
performs the proven operation:

```text
object+0x18 = object+0x1c * factor
```

The preceding `0x84101C00..0x84101D50` and the first block of
`0x84101D54` update the scalar `+0x1c` toward an age-selected target using
signed halfwords scaled by the ROM's `0.001f` constant, with clamping at the
target.  This is a table-driven scalar/size path, not evidence for a generic
three-axis Euler step.

The final position assembly in `0x841027B4` is explicit.  After the optional
call to `0x84101D54`, the three output position fields are:

```text
object+0x20 = object+0x38 + object+0x2c + object+0x44 + object+0x50
object+0x24 = object+0x3c + object+0x30 + object+0x48 + object+0x54
object+0x28 = object+0x40 + object+0x34 + object+0x4c + object+0x58
```

These are four ordered `add.s` operations per axis at
`0x84102820..0x8410287C`.  The linked renderer then receives those positions
and receives the scalar `object+0x18` in each of its three scale slots at
`0x841028B4..0x841028D8`; rotations are copied from `+0x6a/+0x6c/+0x6e`.
No audited instruction establishes `position += velocity * dt`, a velocity
before/after-position ordering, damping, or a 30 Hz floating-point delta.
The implementation should preserve the table-driven fields and keep any
unresolved controller arithmetic behind an explicit resolver rather than
installing an Euler guess.

`0x84105930..0x84105984` is a small helper used to refresh a base three-vector
from global context and a scalar: it computes each destination component as
`globalBase + scalar * globalScale`.  It is not a lifetime function.

## Cleanup owner and main-segment calls

The common pass owns cleanup, not the transform routine:

```text
0x841029DC  dispatch/update one active object
0x8410009C  evaluate done predicate
0x8410488C  if object+0x0c != NULL, detach linked renderer
0x84100350  clear flags/+0x92, unlink object, clear +0x98
```

`0x8410488C..0x841048B4` loads the linked renderer pointer from particle
`+0x0c` and calls `0x84104818`.  The latter scans the global renderer slots
(`0x8419D2A0`, stride `0x16c`), clears the matching slot's bookkeeping, and
calls the main-segment function `0x8003F1DC` at `0x84104874`.  The available
main disassembly proves that `0x8003F1DC..0x8003F20C` calls `0x8006D438` on
the renderer/resource object, clears its pointer at `+0x0c`, and clears bit 0
of its byte at `+0x01`.  This is the concrete external cleanup side effect.

The other main-segment call on the common placement path is
`0x8003C9B8`, called at `0x8410279C` by `0x84102750`.  Its audited body
(`0x8003C9B8..0x8003CA24`) treats `a0+0xa7` as an entry count, scans
16-byte entries comparing signed `a1` against entry `+0xa8`, optionally
copies three words from `+0xac/+0xb0/+0xb4` to `a2`, and returns the matching
entry pointer or zero.  It is an attachment/resource lookup; it does not
increment age or own expiry.  Exact provenance of the lookup object is left
unresolved because it crosses the overlay's linked renderer data.

## ROM-backed implementation fixtures

These fixtures isolate the native ordering and should be useful when updating
the Lua harness:

1. **Ordinary endpoint:** initialize `+0x92=1`, `+0x98=1`, age `+0x7f=0xfe`,
   and flags `+0x14=0`.  One engine tick must first present age `0xff` to the
   category update, then return done and run detach/release (`+0x98=0`,
   `+0x92=0`, flags zero).
2. **Special age gate:** use flags `+0x14 |= 0x20000`, age `0xfe`, and
   `+0x24=1.0f`.  The tick reaches age `0xff` but remains active; the next
   tick wraps age to 0.  Changing `+0x24` to `0.0f` must make the post-update
   predicate terminate at any age.
3. **Authored `+0x80` is not expiry:** select a scale entry whose signed
   `+0x06` is 1, verify `0x84106814` stores byte 1 at `+0x80`, and verify that
   this alone does not make `0x8410009C` return done.
4. **Countdown is separate:** with flags `0x800` and `+0x81=2`, ticks must
   produce countdown 1, then clear `0x800` at countdown 0 without advancing
   `+0x7f`; only the following tick advances age.
5. **Post-increment controller sample:** start age 0 and a category-0/1/7
   object with resolvable transform tables.  The first call to
   `0x84101D54` must receive age 1.  Compare the resulting positions against
   the four-term sum above and keep the unresolved `0x811001A0` transform
   behind a resolver.
6. **Cleanup side effect:** attach a renderer slot, force the done predicate,
   and assert the `0x84104818 -> 0x8003F1DC` call clears the renderer's `+0x0c`
   and byte-`+0x01` bit 0 before the pool object is released.

## Unresolved points

The following are not established by the supplied fragment/main disassembly:

* the semantic name and full external arithmetic of the `0x811000..` and
  `0x811001A0` calls;
* whether a terminal age-`0xff` update is visible to the eventual RDP draw,
  since detach occurs after the update but the renderer submission is in a
  later pass;
* specialized category 2/4/5/6/8 motion behavior;
* any authored `+0x80` lifetime interpretation outside this common pool
  termination predicate.
