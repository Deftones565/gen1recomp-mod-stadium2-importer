# Fragment-79 lifecycle-family audit (W2-R3)

This is a ROM-backed map of the thirty native lifecycle rows.  The supported
US Stadium 2 ROM is `baseroms/stadium2.z64` (MD5
`1561c75d11cedf356a8ddb1a4a5f9d5d`).  Fragment 79 is copied at ROM offset
`0x36F890` to VRAM `0x84100000`; all addresses below are VRAM addresses.  For
an instruction address `A`, the audit used ROM offset
`0x36F890 + (A - 0x84100000)`.  The table rows are at
`0x84183700` (init), `0x84183778` (update), and `0x841837F0` (draw), four
bytes per family.  Disassembly was performed with `mips-linux-gnu-objdump`
on the overlay bytes covering the callback region.

## Scope and evidence boundary

The callback ranges and direct calls below are exact.  A callback's direct
callee is not treated as understood merely because it has a descriptive
name: resource/model ownership, caller arguments, and return-value semantics
that cross that callee remain unresolved.  No move type, move name, visual
category, side rule, camera rule, scale formula, or guessed lifetime is added.

Every non-empty draw callback writes one eight-byte display-list record to the
global command-buffer cursor at `0x800D0510`: opcode `0xDA380003` and pointer
`0x841A4D08`, then calls its family draw helper.  Family 12 gates this write on
its counter.  This proves a draw packet shape and a shared global model/display
object pointer; it does **not** prove which archive resource or model that
pointer denotes.

## Reachability and route impact

Scanning both dispatch channels for all 251 move rows gives 34 lifecycle route
entries and 29 distinct moves.  Eighteen entries are encoded in the alternate
(`0x3000` family-bank) channel.  There is one route entry per move/channel in
this ROM; the affected moves are listed below as `P` (primary) and `A`
(alternate):

| Family | Routed moves | Entries | Distinct moves |
| ---: | --- | ---: | ---: |
| 0 | 60:P* | 1 | 1 |
| 1 | — | 0 | 0 |
| 2 | 129:P* | 1 | 1 |
| 3 | 75:P* | 1 | 1 |
| 4 | 20:P, 35:P, 132:P | 3 | 3 |
| 5 | 62:P* | 1 | 1 |
| 6 | 81:P, 169:P | 2 | 2 |
| 7 | 57:P* | 1 | 1 |
| 8 | 63:P* | 1 | 1 |
| 9 | 95:P*, 103:P*, 173:P* | 3 | 3 |
| 10 | 47:P*, 195:P* | 2 | 2 |
| 11 | 45:P*, 48:P*, 134:P | 3 | 3 |
| 12 | 49:P* | 1 | 1 |
| 13 | 58:P* | 1 | 1 |
| 14 | — | 0 | 0 |
| 15 | 80:P* | 1 | 1 |
| 16 | 131:P | 1 | 1 |
| 17 | 40:P, 41:P, 42:P | 3 | 3 |
| 18 | 76:P* | 1 | 1 |
| 19 | — | 0 | 0 |
| 20 | 161:P* | 1 | 1 |
| 21 | 50:P | 1 | 1 |
| 22 | — | 0 | 0 |
| 23 | 20:A, 35:A, 132:A | 3 | 3 |
| 24 | — | 0 | 0 |
| 25 | — | 0 | 0 |
| 26 | 81:A | 1 | 1 |
| 27 | 50:A | 1 | 1 |
| 28 | — | 0 | 0 |
| 29 | — | 0 | 0 |

`*` means the encoded value was `0x3000 + family`; `P` and `A` are the primary
and alternate move-table channels.  The 24 non-empty rows are not all reachable:
families 19 and 29 have complete table triples but no move route in the 251-row
scan.  The six empty table rows are 1, 14, 22, 24, 25, and 28.

## Callback family map

The range end is the final instruction's address (including the return delay
slot).  `partial` means the callback's own state accesses/control flow are
decoded, but a behaviorally important direct callee is outside this callback
range.  `empty` is an exact all-zero table row, not a missing disassembly.

| ID | Table entries (I/U/D) | Exact callback ranges | Group and direct-call fingerprint | Persistent state / termination evidence | Status |
| ---: | --- | --- | --- | --- | --- |
| 0 | `59198/591C8/591E8` | `59198..591C4`, `591C8..591E4`, `591E8..59238` | Shared wrapper: init calls `56BA0, 66F60, 58F00`; update `677C4`; draw `68000` | No direct state slot; return/lifetime delegated | partial |
| 1 | `0/0/0` | — | No callback bytes | No state or termination | empty |
| 2 | `572A0/572D4/57344` | `572A0..572D0`, `572D4..57340`, `57344..57394` | Timer/model group; init `56BA0, 62660, 57128`; update `57128, 62C88`; draw `62DE8` | Counter `0x841A4D4C`; update increments; at frames 1770..1800 inclusive, invokes `57128` every 3 frames; outside window passes `-1` into `62C88` | partial |
| 3 | `57AB0/57ADC/57C58` | `57AB0..57AD8`, `57ADC..57C54`, `57C58..57CAC` | Stochastic/controller sibling of 15; init `56BA0, 66130`; update uses `56920, 568A0`, three calls to `0x8007AFA0`, then `66270, 6691C`; draw `66A64` with `a1=34` | Counter `0x841A4D54`; update frame parity and float/RNG path are exact; no direct expiry return proven | partial |
| 4 | `56E58/56E8C/56EFC` | `56E58..56E88`, `56E8C..56EF8`, `56EFC..56F4C` | Timer/model sibling of 6/21; init `56BA0, 5C530, 56CCC`; update `56CCC, 5DAE4`; draw `5DBBC` | Counter `0x841A4D4A`; increment; helper call on frames 120..180 inclusive where `frame % 7 == 0`; `5DAE4` always called; no caller-level expiry proof | partial |
| 5 | `58BA8/58BD8/58BF8` | `58BA8..58BD4`, `58BD8..58BF4`, `58BF8..58C48` | Shared wrapper: init `56BA0, 66F60, 58914`; update `677C4`; draw `68000` | No direct state slot; return/lifetime delegated | partial |
| 6 | `57558/5758C/575FC` | `57558..57588`, `5758C..575F8`, `575FC..5764C` | Timer/model sibling of 4/21; init `56BA0, 5C530, 57398`; update `57398, 5DAE4`; draw `5DBBC` | Counter `0x841A4D4E`; same 120..180 and modulo-7 gate as family 4; no caller-level expiry proof | partial |
| 7 | `56BD4/56C40/56C60` | `56BD4..56C3C`, `56C40..56C5C`, `56C60..56CB0` | Standalone float setup; init `568A0, 56BA0`, two conditional `5A9E4`; update `5AD58`; draw `5ADE0` | No direct state slot; init compares a float and passes `a0=-1/1`, `a2=18000` to `5A9E4`; lifetime delegated | partial |
| 8 | `59C2C/59C6C/59CC8` | `59C2C..59C68`, `59C6C..59CC4`, `59CC8..59D0C` | Related to shared wrapper but has cadence: init `56BA0, 66F60, 597AC, 68540, 59A50`; update `59A50, 69040, 677C4`; draw `68000` | Counter `0x841A4D50`; increment and `frame % 10 == 0` helper call; no direct expiry proof | partial |
| 9 | `57EB0/57EE0/57F00` | `57EB0..57EDC`, `57EE0..57EFC`, `57F00..57F50` | Parameterized model sibling of 10/11; init `56BA0, 568A0, 5F0D0` with `a0=1800`; update `5F9A0`; draw `5FD8C` | No direct state slot; lifetime/model ownership delegated | partial |
| 10 | `57F54/57F84/57FA4` | `57F54..57F80`, `57F84..57FA0`, `57FA4..57FF4` | Parameterized model sibling of 9/11; init `56BA0, 568A0, 603A0`; update `60CD8`; draw `61018` | No direct state slot; lifetime/model ownership delegated | partial |
| 11 | `57FF8/58028/58048` | `57FF8..58024`, `58028..58044`, `58048..58098` | Parameterized model sibling of 9/10; init `56BA0, 568A0, 614E0`; update `61DAC`; draw `621A4` | No direct state slot; lifetime/model ownership delegated | partial |
| 12 | `5809C/580C8/58308` | `5809C..580C4`, `580C8..58304`, `58308..5836C` | Complex stochastic/controller family; init `56BA0, 639D0`; update calls `568E0`, `0x80073F70`, `0x8007E9C0`, `0x80070C14`, `0x8007AFA0`, `63B4C`, `641EC`; draw `64280` | Counter `0x841A4D00`; update increments, runs only for frames 4..49, returns `-1` at 50+; draw skips command-list write while counter <2 | partial |
| 13 | `58E24/58E58/58EAC` | `58E24..58E54`, `58E58..58EA8`, `58EAC..58EFC` | Cadenced controller family related to 8; init `56BA0, 68540, 58C4C`; update `58C4C, 69040`; draw `69618` | Counter `0x841A4D48`; increment and `frame % 10 == 0` helper call; no direct expiry proof | partial |
| 14 | `0/0/0` | — | No callback bytes | No state or termination | empty |
| 15 | `57CB0/57CDC/57E58` | `57CB0..57CD8`, `57CDC..57E54`, `57E58..57EAC` | Same stochastic/controller shape as 3; init `56BA0, 66130`; update `56920, 568A0`, three calls to `0x8007AFA0`, then `66270, 6691C`; draw `66A64` with `a1=34` | Counter `0x841A4D56`; update frame parity and float/RNG path are exact; no direct expiry return proven | partial |
| 16 | `58370/5839C/58520` | `58370..58398`, `5839C..5851C`, `58520..58584` | Complex controller family; init `56BA0, 647D0`; update `569E0`, `0x8007E9C0`, `0x80073F70`, `64924, 65008`; draw `650A8` | Counter `0x841A4D02`; update increments and has a four-frame phase gate; no direct expiry return proven | partial |
| 17 | `58588/586C8/58714` | `58588..586C4`, `586C8..58710`, `58714..58764` | Complex init/controller sibling; init has 104-byte frame and calls `56BA0, 65510, 569E0, 65670, 0x84109B88`; update `65C2C`; draw `65CC0` | Counter `0x841A4D04`; update increments and returns `-1` at frame 50+, otherwise calls `65C2C` | partial |
| 18 | `59708/59738/59758` | `59708..59734`, `59738..59754`, `59758..597A8` | Shared wrapper: init `56BA0, 66F60, 59584`; update `677C4`; draw `68000` | No direct state slot; return/lifetime delegated | partial |
| 19 | `594E0/59510/59530` | `594E0..5950C`, `59510..5952C`, `59530..59580` | Shared wrapper: init `56BA0, 66F60, 5923C`; update `677C4`; draw `68000` | No direct state slot; complete table triple but no reachable move route found | partial |
| 20 | `58840/58874/588C0` | `58840..58870`, `58874..588BC`, `588C0..58910` | Timer/model sibling; init `56BA0, 5C530, 58768`; update only `5DAE4`; draw `5DBBC` | Counter `0x841A4D06`; increment; returns `-1` at 181+ and otherwise calls `5DAE4`; no modulo spawn gate | partial |
| 21 | `579B8/579EC/57A5C` | `579B8..579E8`, `579EC..57A58`, `57A5C..57AAC` | Timer/model sibling of 4/6; init `56BA0, 5C530, 5782C`; update `5782C, 5DAE4`; draw `5DBBC` | Counter `0x841A4D52`; same 120..180 and modulo-7 gate as family 4; no caller-level expiry proof | partial |
| 22 | `0/0/0` | — | No callback bytes | No state or termination | empty |
| 23 | `56F50/56FC8/56FE8` | `56F50..56FC4`, `56FC8..56FE4`, `56FE8..57038` | Stochastic/model-parameter sibling of 26/27; init 64-byte frame, `56BA0, 56980, 56940, 56BA0, 5BBA0`; update `5BD48`; draw `5C2E0` | No persistent global slot written directly; init constructs random/color arguments and delegates allocation/lifetime | partial |
| 24 | `0/0/0` | — | No callback bytes | No state or termination | empty |
| 25 | `0/0/0` | — | No callback bytes | No state or termination | empty |
| 26 | `57650/576CC/576EC` | `57650..576C8`, `576CC..576E8`, `576EC..5773C` | Same model-parameter shape as 23/27; init 64-byte frame, `56BA0, 568E0, 56900, 56BA0, 5BBA0`; update `5BD48`; draw `5C2E0` | No persistent global slot written directly; exact constants/random argument setup is in init; lifetime delegated | partial |
| 27 | `57740/577B8/577D8` | `57740..577B4`, `577B8..577D4`, `577D8..57828` | Same model-parameter shape as 23/26; init 64-byte frame, `56BA0, 568E0, 56900, 56BA0, 5BBA0`; update `5BD48`; draw `5C2E0` | No persistent global slot written directly; constants differ from 26; lifetime delegated | partial |
| 28 | `0/0/0` | — | No callback bytes | No state or termination | empty |
| 29 | `5703C/570B4/570D4` | `5703C..570B0`, `570B4..570D0`, `570D4..57124` | Model-parameter sibling of 23/26/27; init calls `56BA0, 569C0, 569A0, 56BA0, 5BBA0`; update calls `5BD48` with `a0=1`; draw calls `5C2E0` | No direct persistent state slot or caller-level termination; allocation/lifetime remains delegated | partial |

The family numbers and table addresses above are read directly from the three
ROM tables. Families 19 and 29 are non-empty but unreachable in the 251-move
dispatch scan. Family 29 is directly selected by its table row at
`0x8415703C/0x841570B4/0x841570D4`; its earlier classification as empty was a
research error corrected by a direct `FxRom.lifecycle` comparison.

## Exact shared draw output

The ordinary draw wrappers all follow the same sequence, with family-specific
callee and sometimes a family-specific conditional before it:

```text
cursor = *(u32 *)0x800D0510
*(u32 *)(cursor + 0) = 0xDA380003
*(u32 *)(cursor + 4) = 0x841A4D08
cursor = family_draw_helper(cursor)
*(u32 *)0x800D0510 = cursor
```

For example, family 7 is `0x84156C60..0x84156CB0`, family 4 is
`0x84156EFC..0x84156F4C`, and family 12 is `0x84158308..0x8415836C`.
Family 12 proves its conditional at `0x84158308..0x84158320`: the record is
not emitted while `*(s16 *)0x841A4D00 < 2`.  The callback writes no archive
resource ID, shape ID, side, camera, or attachment field directly.  Those
inputs may be consumed by the external helpers, but no exact contract was
available in these callback ranges.

## Lifecycle, side, attachment, and ordering conclusions

* **Persistent state:** the timer families explicitly own 16-bit counters at
  `0x841A4D00`, `0x841A4D02`, `0x841A4D04`, `0x841A4D06`, `0x841A4D48`,
  `0x841A4D4A`, `0x841A4D4C`, `0x841A4D4E`, `0x841A4D50`, and
  `0x841A4D52..0x841A4D56` as listed per row.  The other families keep state
  in external objects/helpers or stack temporaries; their persistent layout
  is not proven by the table callbacks.
* **Lifetime/termination:** only family 12 (`counter >= 50`) and family 17
  (`counter >= 50`) visibly return `-1` at the callback level.  Family 20
  visibly returns `-1` at `counter >= 181`.  Families 2, 4, 6, and 21 pass a
  `-1` sentinel or an out-of-window value to an external update helper, but
  the helper's returned status is not proven here.  All other lifetime rules
  remain unresolved.  Do not map timer constants to particle lifetime
  without tracing the caller and helper return contract.
* **Update ordering:** each row's init, update, and draw pointer is an
  independent table entry.  Within an update callback, the evidenced order is
  counter increment/phase test, optional family helper, then any common helper
  (for example `5DAE4` in families 4/6/20/21).  There is no evidence here for
  a global ordering between different lifecycle instances or for update-before-
  draw versus draw-before-update in the owner.  The runtime must preserve a
  deterministic order supplied by its caller until the owner is audited.
* **Side/attachment/camera:** no lifecycle callback shown reads the router's
  side flags, camera-line bit, opposite-side bit, ground precedence, saved
  origin, or scale descriptor.  Those are native particle/object inputs, not
  proven lifecycle-family semantics.  Lifecycle runtime APIs must pass raw
  context through and issue an unsupported diagnostic when a family requires
  one of these unresolved decisions; no side fallback or camera geometry may
  be guessed from the family number or move.
* **Resource/model dependencies:** the common draw record points at
  `0x841A4D08`, and several init/update helpers are clearly model/object
  builders by their call graph, but these callback ranges contain no resource
  archive ID or model-table lookup.  Resource ownership and release must be
  resolved by disassembling the direct callees and their callers.  Treating
  `0x841A4D08` as a shape/resource ID would be incorrect.

## Proposed decoder/runtime API

The decoder should expose the raw row and evidence, without pretending that a
native function pointer is a portable Lua implementation:

```lua
lifecycle = {
  [family] = {
    id = family,
    init = {address = 0x841..., range = {first, last}, empty = false},
    update = {address = 0x841..., range = {first, last}, empty = false},
    draw = {address = 0x841..., range = {first, last}, empty = false},
    state = {address = 0x841A4D4C, width = 2, signed = true}, -- when proven
    routeCount = n,
    routeMoves = { ... },
  }
}
```

The runtime boundary should be explicit and snapshot-oriented:

```lua
local family = decoder.lifecycle[id]
local instance = runtime:spawnLifecycle({
  family = family,
  effectId = effectId,
  context = rawContext,       -- side/attachment/camera fields preserved
  resolver = lifecycleResolver,
})
runtime:step(1)                -- exactly one 30 Hz tick
local packet = runtime:drawPacket(instance)
```

`init`, `update`, and `drawPacket` should return `(value, diagnostic)` and
retain raw inputs on unsupported paths.  Diagnostics must use the frozen
schema `{code,severity,effectId,programId,address,kind,message}`.  An
unsupported family must remain alive until an explicit release or an
ROM-proven termination result; it must not receive a synthetic lifetime.
Draw packets should contain the authored command opcode/pointer and helper
identity, while a renderer adapter decides whether that command is currently
supported.  This preserves callback identity and prevents a procedural stand-in
from being mistaken for Stadium behavior.

## Prioritized implementation sequence and ROM-backed goldens

1. **Decoder/table and route goldens.** Add an immutable decoder test for all
   30 triples, the six empty rows, and families 19/29 as unreachable-but-nonempty,
   34 route entries, 29 moves, and 18 alternate-bank entries.  Include move 20
   (families 4 primary/23 alternate), move 50 (21 primary/27 alternate), and
   move 81 (6 primary/26 alternate) to exercise paired banks.
2. **Shared draw packet.** Implement only the proven eight-byte
   `0xDA380003/0x841A4D08` packet and cursor update.  Golden families 4
   (`0x84156EFC..0x84156F4C`), 7 (`0x84156C60..0x84156CB0`), and 12's
   counter gate (`0x84158308..0x8415836C`) should compare exact command words
   and cursor movement.
3. **Counter/timer state.** Implement raw signed-16 counters and 30 Hz
   increment/order for families 2, 4, 6, 8, 13, 20, and 21.  Goldens should
   test family 4 at frames 119/120/126/180/181, family 2 at 1769/1770/1773/
   1800/1801, family 12 at 1/2/49/50, and family 20 at 180/181.  External
   helper status remains a resolver result, not a guessed expiry.
4. **Parameter/model siblings.** Trace callees before implementing families
   9/10/11 and 23/26/27.  Goldens must record exact callee arguments, constants,
   stack-produced vectors/colors, and raw helper return values.  Do not turn
   their constants into shape categories or side rules.
5. **Complex stochastic/controller families.** Audit the external callees and
   caller context for families 3/15, 12, 16/17, and 0/5/18/19.  Goldens must
   inject RNG and compare resolver call order and raw arguments.  No host battle
   RNG may be consumed.
6. **Attachment/resource integration last.** Only after direct callee and
   owner disassembly proves the model/resource and side/camera contracts should
   lifecycle snapshots be connected to the renderer or battle scene.

The existing material/motion audit supplies the same conservative rule for
unresolved controllers: preserve authored pointers and raw fields, return a
structured diagnostic, and defer formulas until the ROM owner is identified.
