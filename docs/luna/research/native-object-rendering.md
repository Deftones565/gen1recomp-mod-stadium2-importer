# Fragment 79 native-object rendering ABI

## Scope and evidence

This report is a rendering handoff for the supported Pokemon Stadium 2 US
ROM. The fragment-79 image is the ROM range `0x36F890..0x419480`, loaded at
`0x84100000`; the disassembly command used for the ranges below was:

```sh
mips-linux-gnu-objdump -D -b binary -m mips:isa64 -EB \
  --adjust-vma=0x84100000 /tmp/stadium2_fragment79.bin
```

The conclusions below are instruction-level facts from the US image. A field
is called a geometry field only when a local routine reads or writes it as
part of the visual path. Names such as `position`, `material`, and `bone`
are intentionally not assigned where the ROM does not prove that meaning.

## Resolver ABI and command decoding

All five native-object opcode handlers read the current command cursor from
global `0x84190170`, pass the command's word at `+4` in `a0` to external
`0x80003240`, and receive the resolved object pointer in `v0`. The command
cursor is then advanced by eight bytes. The call sites are:

| opcode | mode | handler | resolver call | input load | resolved pointer save |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 5 | 2 | `0x84108060` | `0x84108070` | `lw a0,4(v0)` | `sw v0,0(slot)` at `0x841080A8` |
| 6 | 4 | `0x841080F8` | `0x84108108` | `lw a0,4(v0)` | `sw v0,0(slot)` at `0x84108140` |
| 7 | 5 | `0x84108228` | `0x84108238` | `lw a0,4(v0)` | `sw v0,0(slot)` at `0x84108270` |
| 13 | 6 | `0x841082C0` | `0x841082D0` | `lw a0,4(v0)` | `sw v0,0(slot)` at `0x84108308` |
| 15 | 8 | `0x84108190` | `0x841081A0` | `lw a0,4(v0)` | `sw v0,0(slot)` at `0x841081D8` |

The resolver ABI therefore has one proven argument (the encoded command
pointer) and one proven return value (a pointer). No second argument is set
at these call sites. The body of `0x80003240`, its lookup tables, ownership,
and whether it returns the encoded pointer unchanged are outside fragment 79
and remain unresolved. A renderer must retain both values:

```text
commandPointer = command record word +4
resolvedObject = resolver return v0 -> scheduler slot +0
```

The constructor copies the resolved-object timing byte as follows:

| mode | constructor | source | slot destination |
| ---: | ---: | --- | --- |
| 2 | `0x84108060..0x841080F8` | resolved `+0x00` low byte (`lw` at `0x841080B0`) | slot `+4` |
| 4 | `0x841080F8..0x84108190` | resolved `+0x00` low byte (`lw` at `0x84108148`) | slot `+4` |
| 5 | `0x84108228..0x841082C0` | resolved `+0x00` low byte (`lhu` at `0x84108278`, low byte) | slot `+4` |
| 6 | `0x841082C0..0x84108358` | resolved `+0x00` low byte (`lhu` at `0x84108310`, low byte) | slot `+4` |
| 8 | `0x84108190..0x84108228` | resolved `+0x00` low byte (`lw` at `0x841081E0`) | slot `+4` |

Because the resolved pointer is dereferenced at offset zero, the practical
timing byte is byte `+3` for modes 2/4/8 and byte `+1` for modes 5/6 on the
big-endian MIPS object. Every constructor writes reload `+5=0`, state
`+7=1`, the mode at `+9`, and leaves `+10..+11` untouched.

## Exact scheduler update table

The mode table is at `0x84188C7C`; the scheduler at
`0x84107B68..0x84107CD4` indexes it with `slot[+9] * 4`. The raw table words
for modes 0 through 8 are:

```text
0: 84107BE8    1: 84107BF8    2: 84107C18
3: 84107C60    4: 84107C28    5: 84107C38
6: 84107C48    7: 84107C08    8: 84107C58
```

The target wrappers and their local visual-update bodies are:

| mode | table target | wrapper action | local body | visual initializer / action |
| ---: | ---: | --- | --- | --- |
| 2 | `0x84107C18` | `jal 0x841076B8`, then return signed slot `+7` | `0x841076B8..0x841077E4` | `0x84107170`, then `0x8410679C`, `0x84106AC4`, `0x84106F34` |
| 4 | `0x84107C28` | `jal 0x84107838`, then return signed slot `+7` | `0x84107838..0x841078B4` | allocates blocks and calls `0x84104F54` |
| 5 | `0x84107C38` | `jal 0x84107948`, then return signed slot `+7` | `0x84107948..0x84107994` | common mode-5/6 visual allocation |
| 6 | `0x84107C48` | `jal 0x84107948`, then return signed slot `+7` | shared with mode 5 | common mode-5/6 visual allocation |
| 8 | `0x84107C58` | `jal 0x841078B8`, then return signed slot `+7` | `0x841078B8..0x84107944` | allocates large mode-8 block |

The scheduler decrements slot `+4` at `0x84107BA4..0x84107BB8` and dispatches
on the same tick when it reaches zero (`0x84107BBC`). A positive callback
return is processed at `0x84107C64`: `0xFF` reloads `+4` from `+5`; every
other positive result increments age `+6` and releases when it equals the
result. A non-positive result leaves the slot active. The target constructors
set `+5=0` and wrappers return `+7=1`, so a normal successful callback is
one-shot at the scheduler level; this does not prove the visual object's
independent lifetime.

## Mode 2: concrete drawable family

Mode 2 is the best implementation fixture because it is retail-covered and
its callback allocates a visible-object batch. The command family at
`0x8416A3E0` appears in 13 moves and 12 programs (including program 98). Its
first 32 ROM bytes are:

```text
00 00 00 23 84 16 A3 D8 00 00 00 14 84 16 A3 D8
00 00 00 1E 84 16 A3 D8 00 00 00 28 84 16 A3 D8
```

The mode-2 record for program 98 is at `0x84173DA4`. The constructor timing
byte is `+3 = 0x23`, and the callback's visual-allocation loop reads the same
byte from the resolved object at `0x841076EC` / `0x841077AC`. Under an
identity resolver this is a 35-iteration visual batch; the renderer must use
the resolver result rather than assume identity.

The family occurs in moves:

```text
7, 8, 9, 36, 38, 55, 61, 99, 117, 137, 145, 170, 183
```

The encoded object points repeatedly reference `0x8416A3D8` in this fixture:

```text
resolved candidate 0x8416A3D8:
  +0x00 = 0x8416A310
  +0x04 = 0x8416A3D0
  +0x08 = 0x00000023
  +0x0C = 0x8416A3D8
  +0x10 = 0x00000014
  +0x14 = 0x8416A3D8
  +0x18 = 0x0000001E
  +0x1C = 0x8416A3D8
```

These values are pointer-graph evidence only; the external resolver still
decides the actual returned object.

The mode-2 body (`0x841076B8`) performs, per loop iteration:

1. `0x84100328()` allocates a visual object.
2. `0x84107170(slot, visual)` copies the resolved pointer to visual `+0x10`,
   slot mode to visual `+0x7C`, slot `+10` to visual `+0x68`, and global
   `0x84190194` to visual `+0x08`.
3. It applies visual flag mask `0x3000` via `0x84100020`.
4. `0x8410679C(visual, slot, loopIndex, 1.0f)` follows the object pointer at
   resolved `+0x0C`, reads a selector halfword at nested `+0`, and uses nested
   pointers at `+4`, `+8`, `+0xC`, and `+0x10`. It writes selected data into
   visual offsets including `+0x1C`, `+0x6A..+0x6E`, `+0x7D`, and `+0x80`.
5. `0x84106AC4(visual, resolvedObject, loopIndex, 1.0f)` applies further
   object-graph vectors/rotations.
6. The callback reads authored values at visual `+0x20/+0x24` and adds the
   constants `40.0f`/`120.0f` to those two values, writes the results back to
   `+0x20/+0x24`, and publishes the constants at `+0x44/+0x48`. It then calls
   `0x84106F34(visual, resolvedObject)` to copy additional authored bytes and
   allocate visual-side buffers.

The visible-object pool is separate from the 64 scheduler slots. Its frame
dispatcher is `0x841029DC..0x84102B38`, global pool `0x8418C950`, 300 entries,
156-byte stride. It tests active byte `+0x98`, dispatches on mode byte `+0x7C`
through `0x84188BB0`, and then calls the generic state check
`0x8410009C`. A release calls `0x8410488C` followed by `0x84100350`.

## Exact draw table and mode 2/5/8 draw paths

The raw draw table is at `0x84188BB0`. Its words for modes 0 through 8 are:

```text
0: 84102A3C    1: 84102A54    2: 84102A9C
3: 84102AF4    4: 84102AAC    5: 84102ADC
6: 84102AEC    7: 84102A78    8: 84102ACC
```

The relevant draw wrappers are:

| mode | draw-table target | body called | proven reads/writes |
| ---: | ---: | --- | --- |
| 2 | `0x84102A9C` | `0x84100B3C(visual)` | follows visual `+0x10`, object `+4` list, visual `+0x7F` index; selected bytes become visual `+0x8B..+0x8E` or are passed to `0x8410A4F8` |
| 5 | `0x84102ADC` | `0x84100C68(visual)` | follows visual `+0x10`, object `+4` and `+8` lists, visual `+0x7F` index; passes selected four-byte records to externals `0x8003F454` and `0x8003F4DC` |
| 8 | `0x84102ACC` | `0x84100B3C(visual)` | shares mode-2 draw body; constructor additionally initializes fixed floats below |

Mode 2/8 draw body `0x84100B3C` reads `visual+0x10` as the resolved object,
then `object+4` as a list head. Each list element supplies a pointer at `+0`
and a next pointer at `+4`; the pointed record's byte `+2` is a count and
byte `+0` selects direct versus indexed data. The visual byte `+0x7F` is
reduced modulo that count. A selected four-byte record is either copied to
visual `+0x8B..+0x8E` (non-mode-2 path) or passed bytewise to local
`0x8410A4F8` for mode 2. No battler or camera pointer is read in this draw
body.

Mode 8 constructor `0x841078B8..0x84107944` allocates a visual-side block of
`0x7028` bytes at visual `+0x14` through external allocator `0x81100020`,
stores the resolved pointer at `+0x10`, mode at `+0x7C`, and writes:

```text
visual +0x20 = visual +0x44 = 40.0f  (0x43200000)
visual +0x24 = visual +0x48 = 120.0f (0x42F00000)
```

Mode 5/6 constructor `0x84107948..0x84107994` allocates a visual, stores the
resolved pointer at `+0x10`, and copies slot mode to `+0x7C`; it does not run
the mode-2 geometry helpers. Mode 5 draw body `0x84100C68` selects records
from the two object lists and calls local selectors `0x84100874`/
`0x841009D8`, then external `0x8003F454` (first selected record plus byte
`+3`) and `0x8003F4DC` (second selected record plus byte `+3`). Their ABIs and
resource/rendering effects are unresolved.

## Mode 5 implementation fixture

The most useful retail mode-5 family with a nonzero constructor delay is
encoded pointer `0x8417B8AC`. It is used by four moves (`189` is the only
move in the direct route catalog for this family's program 328) and program
328's mode-5 record is at `0x841788B8`. Its first 32 bytes are:

```text
00 02 00 00 84 17 B8 A0 02 EE 04 B0 00 1E 00 00
00 00 FF FB 00 02 00 05 00 05 00 02 FF FB 00 05
```

Mode 5 reads resolved byte `+1 = 0x02` as the initial countdown. The words at
`+4`, `+8`, and `+0xC` are pointer/graph candidates consumed only after the
external resolver result is installed; the mode-5 draw body must not treat
the encoded command bytes as a complete object schema.

## Exact unresolved boundaries

The following are known call boundaries but are not safe to implement as
guessed geometry or lifetime rules:

* `0x80003240`: command-pointer resolver; input lookup and object ownership.
* `0x81100020`: visual-side allocation used by modes 4 and 8.
* `0x81100054` / `0x81100074`: visual/resource allocation or cleanup helpers
  reached by draw and helper paths.
* `0x8003F454` / `0x8003F4DC`: mode-5 draw-side resource/render callbacks.
* `0x8003EC34`: external callback reached by generic visual state handling.
* `0x84190194`: global visual context pointer copied to visual `+8`; its
  owner and battler/camera meaning are not proven.
* `0x8410679C`, `0x84106AC4`, `0x84106F34`, `0x84100710`, `0x84100874`,
  `0x841009D8`, and `0x8410A4F8`: local helpers whose pointer graphs and
  selected-record semantics are partially proven above, but whose complete
  output layouts are not yet recovered.
* `0x8410009C`, `0x8410488C`, `0x84100350`: generic visual state/release
  chain; release ordering is proven, visual lifetime policy is not.

No native mode constructor in the recovered ranges reads a battler or camera
address directly. Placement therefore requires an injected scene adapter
backed by recovered object/context evidence. Until the resolver and helper
ABIs are linked, emit a native-object packet carrying the raw command,
resolved-pointer evidence, mode, slot timing, visual callback state, and an
explicit unresolved-placement/geometry diagnostic; do not synthesize a
particle, matrix, shape, or move-type visual.
