# Fragment 79 native-object scheduler modes

Historical audit: several body mappings, flag calls and float values below
were incorrect. See [verified implementation](native-callbacks-implemented.md)
before using these notes as evidence.

## Scope and provenance

This is a ROM-only pass over the supported `Pokemon Stadium 2 (USA).z64`.
Fragment 79 was extracted from ROM offset `0x36F890` through `0x419480` and
loaded at `0x84100000`; the executable/data window therefore ends at
`0x841A7BF0`.  The disassembly was produced with:

```sh
dd if='Pokemon Stadium 2 (USA).z64' of=/tmp/stadium2_fragment79.bin \
  bs=1 skip=$((0x36F890)) count=$((0x419480-0x36F890)) status=none
mips-linux-gnu-objdump -D -b binary -m mips:isa64 -EB \
  --adjust-vma=0x84100000 /tmp/stadium2_fragment79.bin
```

Addresses and instruction ranges below are VRAM addresses.  A value described
as a “raw table word” is the four bytes present in the overlay.  Several of
the callback-table words carry overlay/relocation prefixes rather than a
standalone fragment-79 VRAM address; they are not normalized here.

## Result in one paragraph

The target opcodes do not encode a particle-emitter header.  They enqueue an
8-byte command, call an external resolver at `0x80003240`, allocate one of 64
12-byte scheduler slots, and put the resolver's returned pointer in the slot.
The constructor then derives the slot's initial delay from one byte of the
resolved object: modes 2, 4, and 8 use resolved-object byte `+3`, while modes
5 and 6 use byte `+1`.  All five constructors set reload byte `+5` to zero,
control byte `+7` to one, and mode byte `+9` to the mode number.  The current
decoder's `descriptor = record.argument`, four-byte raw copy, and
`interval=0/repeats=1` happen to preserve the command pointer but do not yet
model the resolver or the resolved object layout.  Modes 2, 4, and 8 occur in
the retail catalog; modes 4 and 6 have no records in any of the 395 programs.

## Opcode and constructor evidence

The opcode table is at `0x8416A218`, with eight bytes per row.  The relevant
rows are:

| opcode | mode written | handler | handler range | constructor reads from resolved pointer |
| ---: | ---: | ---: | --- | --- |
| `5` | `2` | `0x84108060` | `0x84108060..0x841080F8` | `lw` at `0x841080B0`; `sb` low byte to slot `+4`; this is byte `+3` on big-endian MIPS |
| `6` | `4` | `0x841080F8` | `0x841080F8..0x84108190` | `lw` at `0x84108148`; low byte to slot `+4`; resolved byte `+3` |
| `7` | `5` | `0x84108228` | `0x84108228..0x841082C0` | `lhu` at `0x84108278`; low byte to slot `+4`; resolved byte `+1` |
| `13` | `6` | `0x841082C0` | `0x841082C0..0x84108358` | `lhu` at `0x84108310`; low byte to slot `+4`; resolved byte `+1` |
| `15` | `8` | `0x84108190` | `0x84108190..0x84108228` | `lw` at `0x841081E0`; low byte to slot `+4`; resolved byte `+3` |

Each target constructor has the same control flow (the mode-2 range is the
clearest copy):

* It loads the current 8-byte command cursor from global `0x84190170` and
  passes command word `+4` to external `0x80003240` (`0x84108060..0x84108074`
  for mode 2; corresponding ranges are the starts of the other four handler
  ranges above).
* It calls the 64-slot allocator `0x84105DD0` and publishes the resulting
  slot at global `0x84190174` (`0x84108078..0x84108088` for mode 2).
* On success, the external resolver's return value (saved by the `jal` delay
  slot at `0x8410807C`) is stored as slot word `+0` at `0x841080A8`.  This is
  why the command argument and the eventual slot descriptor must be separate
  fields in a future decoder schema.
* It writes slot `+4`, zeroes slot `+5`, writes one to slot `+7`, writes the
  literal mode to slot `+9`, and advances the command cursor by eight bytes.
  The mode-5 range uses `0x84108284..0x841082A4`; the mode-6 range uses
  `0x8410831C..0x8410833C`; mode 8 uses `0x841081EC..0x8410820C`.
* A failed allocation clears the command cursor; no scheduler slot is
  created.

The external call at `0x80003240` is outside fragment 79.  Its exact lookup
rule and whether it returns the command pointer unchanged are unresolved.
The ROM proves only that its return value becomes slot word `+0` and is then
treated as a pointer.

## Scheduler slot and timing

Initialization is `0x84105DD0..0x84105E1C`; the pool is allocated as 768 bytes
(64 slots × 12) at global pointer `0x84190150` (`0x84105D08..0x84105D38`).
Allocation scans 64 slots with 12-byte stride and tests active bit 0 of byte
`+8` (`0x84105D40..0x84105DCC`).  The proven slot layout is:

| offset | proven use |
| ---: | --- |
| `+0..+3` | resolved native-object pointer, supplied by `0x80003240` |
| `+4` | current countdown; constructor's initial delay |
| `+5` | reload countdown; all five target constructors write zero |
| `+6` | callback age/count; scheduler increments it after a non-`0xFF` callback result |
| `+7` | callback return/state value; allocator initializes one and target wrappers return it |
| `+8` | active flag bit 0 |
| `+9` | mode (`2`, `4`, `5`, `6`, or `8`) |
| `+10..+11` | untouched by these five constructors; not assigned a meaning here |

The frame driver calls scheduler update at `0x84105600`; the scheduler is
`0x84107B68..0x84107CD4`.  It visits all 64 slots, decrements byte `+4`, and
only dispatches when that countdown reaches zero (`0x84107BA4..0x84107BBC`).
It bounds mode to `<9` and loads an indirect update callback from
`0x84188C7C + mode*4` (`0x84107BC4..0x84107BE4`).  The target callback-table
words are direct local VRAM addresses:

| mode | table word at `0x84188C7C + mode*4` |
| ---: | ---: |
| `2` | `0x84107C18` |
| `4` | `0x84107C28` |
| `5` | `0x84107C38` |
| `6` | `0x84107C48` |
| `8` | `0x84107C58` |

The wrapper-to-body mapping is explicit in the `jal` instructions at
`0x84107C08`, `0x84107C28`, `0x84107C38`, `0x84107C48`, and `0x84107C58`:

| mode | table target / wrapper | local body called by wrapper |
| ---: | ---: | ---: |
| `2` | `0x84107C18` | `jal 0x841076B8` |
| `4` | `0x84107C28` | `jal 0x84107838` |
| `5` | `0x84107C38` | `jal 0x84107948` |
| `6` | `0x84107C48` | `jal 0x84107948` |
| `8` | `0x84107C58` | `jal 0x841078B8` |

After the callback returns, a non-positive result leaves the slot alone for
that frame.  `0xFF` reloads byte `+4` from byte `+5` (`0x84107C6C..0x84107C7C`),
otherwise byte `+6` is incremented and compared with the callback result
(`0x84107C80..0x84107C90`).  Equality calls release/reset
`0x84105E20..0x84105E3C`; this clears bytes `+7`, `+8`, `+5`, and `+4`, and
copies the old byte `+7` into byte `+6`.

The mode wrappers in `0x84107BE8..0x84107C60` return slot byte `+7` after
their mode-specific work.  For target modes this is one, so a normal first
callback advances age from zero to one and releases the scheduler slot.  This
is a one-shot scheduler fact, not an assumption about the visual object's
own lifetime.  Since target reload is zero, no repeated scheduler callback is
authored by these constructors.

## Native-object update/constructor families

The following are the local mode-specific callback bodies reached by the
mode wrapper.  The indirect table words above point into the wrapper block in
fragment 79; each wrapper calls its mode-specific body and returns slot byte
`+7` to the scheduler.

### Mode 2 / opcode 5

`0x841076B8..0x841077E4` is the mode-2 callback.  It reads the resolved
object pointer from slot `+0`, then reads resolved-object byte `+3` at
`0x841076EC`.  That byte is used as a loop bound (`0x841077AC..0x841077BC`),
so mode 2 can allocate that many visual objects in one callback.  For each
iteration it allocates a visual object through `0x84100328`, initializes it
through `0x84107170`, sets visual flag mask `0x3000` at `0x84107738`, and
calls the authored geometry/transform helpers `0x8410679C`, `0x84106AC4`, and
`0x84106F34` (`0x84107744..0x841077A8`).  It does not read a battler or camera
pointer directly in this range.

`0x84107170..0x84107210` is a shared visual initializer used by mode 2.  It
copies the resolved pointer to visual `+16` (`0x8410718C`), copies slot mode
to visual `+124` (`0x84107190..0x84107194`), and copies global pointer
`0x84190194` to visual `+8` (`0x841071A4..0x841071A8`).  It reads the word at
resolved-object `+4` (`0x841071AC`) as bit flags and conditionally sets visual
masks `0x1`, `0x40`, `0x200`, and `0x10000` (`0x841071B0..0x8410720C`).
The source of global `0x84190194` and the semantic names of those flags are
not proven here.

The geometry path is pointer-bearing and larger than four bytes.  At
`0x841067BC..0x84106838`, helper `0x8410679C` reads a pointer at resolved
object `+12`, a selector halfword at nested `+0`, and nested pointers at
`+4`, `+8`, `+12`, and `+16`; it writes selected values into the visual,
including fields at `+0x1C`, `+0x6A..+0x6E`, `+0x7D`, and `+0x80`.  It uses
selector helper `0x84106540`.  `0x84106AC4` starts from the visual's
resolved-object graph and applies additional authored vectors/rotations;
`0x84106F34` copies further authored byte/vector data and allocates its
visual-side buffers.  These routines are evidence for pointer graph inputs,
not permission to collapse the object into a particle descriptor.

### Mode 4 / opcode 6

`0x84107838..0x841078B4` allocates a visual through `0x84100328`, allocates
visual-side blocks at `+20` of sizes `8` and `32` through external
`0x81100020` (`0x84107868..0x84107884`), stores the resolved pointer at visual
`+16`, stores mode `4` at visual `+124`, and calls `0x84104F54`
(`0x8410788C..0x841078A0`).  No mode-4 records exist in the retail 395
programs, so this family is a ROM-proven implementation path but has no
catalog instance to use as a behavioral fixture.

### Modes 5 and 6 / opcodes 7 and 13

The two modes share callback body `0x84107948..0x84107994`.  It allocates a
visual through `0x84100328`, stores the mode from slot `+9` into visual `+124`
(`0x84107974..0x84107978`), and stores the resolved pointer into visual `+16`
(`0x8410797C..0x84107984`).  It does not perform the mode-2 geometry calls.
Mode 5 and mode 6 have distinct indirect update-table words, but the same
local visual initializer.  Neither mode 4 nor mode 6 occurs in the 395
programs.

### Mode 8 / opcode 15

`0x841078B8..0x84107944` allocates a visual through `0x84100328`, allocates
visual-side blocks at `+20` of sizes `8` and `0x7028` through `0x81100020`
(`0x84107868..0x84107884` is the analogous mode-4 path; mode 8's calls are
`0x841078E8..0x841078F8`), stores the resolved pointer at visual `+16`, and
stores mode `8` at visual `+124`.  It writes float constants `40.0` and
`120.0` to visual offsets `+32/+68` and `+36/+72` (`0x84107904..0x84107930`;
literal words `0x43200000` and `0x42F00000`).  Their semantic names are not
assigned here.

## Draw and release path

After scheduler update, the frame driver calls `0x841029DC`
(`0x84105608`).  `0x841029DC..0x84102B38` scans a separate 300-entry visual
pool at global pointer `0x8418C950`, with 156-byte stride.  It tests visual
active byte `+0x98` (`0x84102A0C`), reads visual mode byte `+0x7C`
(`0x84102A18`), and dispatches through the raw draw table at
`0x84188BB0 + mode*4` (`0x84102A24..0x84102A38`).  Target draw-table words
are:

| mode | table word at `0x84188BB0 + mode*4` |
| ---: | ---: |
| `2` | `0x84102A9C` |
| `4` | `0x84102AAC` |
| `5` | `0x84102ADC` |
| `6` | `0x84102AEC` |
| `8` | `0x84102ACC` |

The draw target bodies are local fragment-79 entry points.  The dispatcher
does call generic visual
state check `0x8410009C` (`0x84102AF4..0x84102AFC`); when it reports release,
it calls child cleanup `0x8410488C` and visual-pool release
`0x84100350` (`0x84102B04..0x84102B10`).  `0x84100350..0x841003A0` clears
visual pointer links, visual `+20`, and active byte `+0x98`.  This is the
proven release chain.  It is separate from scheduler-slot reset
`0x84105E20`.

No target-mode constructor reads a battler or camera address.  The only
proven attachment/context inputs are the resolved-object pointer, its word
at `+4` consumed as visual flag bits by `0x84107170`, and global pointer
`0x84190194` copied to visual `+8`.  Any battler/camera interpretation and
the external draw callbacks remain unresolved.

## Retail coverage and descriptor-family enumeration

The following counts come from decoding all program IDs `0..394` and all
move routes `1..251`.  “Pointer family” means a distinct encoded command
argument pointer in the retail program stream.  It is intentionally not
called a resolved descriptor until the `0x80003240` lookup is implemented.
“Moves” counts a move once if either its primary or alternate program route
contains that mode.

| mode | opcode | records | programs | pointer families | moves | distinct timing byte values |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `2` | `5` | 195 | 194 | 93 | 104 | 15 (`+3`) |
| `4` | `6` | 0 | 0 | 0 | 0 | 0 |
| `5` | `7` | 121 | 117 | 98 | 89 | 16 (`+1`) |
| `6` | `13` | 0 | 0 | 0 | 0 | 0 |
| `8` | `15` | 87 | 87 | 51 | 55 | 21 (`+3`) |

There are 403 target records and 268 distinct programs in the union.  The
program-set intersections are mode `2∩5 = 81`, `2∩8 = 45`, and `5∩8 = 32`;
all other pairwise intersections are zero.  Thus the 268-program union is
not the sum of the three per-mode program counts.

The complete unique pointer-family inventory is below.  Each line gives the
resolved-object timing byte value used by the constructor, followed by every
encoded pointer with that value.  The four bytes shown in this inventory are
the bytes at the encoded argument pointer in the ROM catalog, not a claim
that they are the complete resolved object.  `P` and `R` counts are omitted
from the compact inventory because the global table above already gives the
program/record totals; repeated pointers are still enumerated exactly once.

### Mode 2 / opcode 5: value is encoded pointer byte `+3`

```text
00: 8416A3B8,8416A3C8,8416A420,8416A438,8416A450,8416A488,8416A4B8,8416A504,8416A51C,8416A538,8416A550,8416A588,8416A5B8,8416A5E8,8416A630,8416A660,8416A690,8416A6C0,8416A6D8,8416A6F0,8416A708,8416A720,8416A738,8416A768,8416A780,8416A7B0,8416A7E0,8416BB3C,8416BBEC,8416BD90,8416C86C,8416D4DC,8416E0CC,8416FA6C,84171914,84171F0C,84173380,841737BC,84174684,841747EC,84174934,84174B3C,84174CDC,8417584C,84175990,841772D4,84179004,8417943C,8417AD40,8417AEC4,8417AFB8,8417C054,8417C6FC,8417CC50,8417EDEC,8417EF18,8417F03C,84180EBC,84181788
08: 8416CA04
14: 8416A3E8
1E: 8416A3F0,8416A4A0,8417C72C
23: 8416A3E0
28: 8416A3F8,8416A600,8416B87C,8416F354,84174A8C,84174C08
29: 84170E90
30: 841775E0
32: 8416A400,8416A468,8416A4D0,8416A568,8416A5A0,8416A5D0,841729F0,8417C084
37: 8416E514
3C: 8416A408,8416A4D8,8416A570
40: 8416A798,8416A7C8,8416A7F8,841719A0
44: 8416D2F0,8416D7A0
46: 8416A750
55: 8416FC0C
```

This is the complete list of 93 mode-2 pointer families.

### Mode 5 / opcode 7: value is encoded pointer byte `+1`

```text
00: 8416A9C8,8416AA54,8416AAD0,8416AB4C,8416AB9C,8416B548,8416B874,8416BB18,8416BBC8,8416C278,8416C7CC,8416CC08,8416E254,8416EDB0,8416F42C,84171628,84171748,8417185C,84171988,84171A5C,84172F24,84172F8C,84173154,8417358C,841737FC,841746A0,84174808,84174950,84174AC0,84174B58,84174C2C,84174F20,84175080,84175108,841751A0,841759CC,84179670,8417AC68,8417AD10,8417C294,8417C4C4,8417C9C0,8417DAB8,8417E160,8417E238,8417EC70,8417EF4C,8417F00C,8418058C,84180E20,84180FFC,84181450,841816A4,84181EA8
02: 84178894,8417B8AC,8417D410,8417E530
04: 8417128C,84172B84,84172D08,84172DD0,84172E7C,841791B4,8417B5C4
06: 84175BF0
08: 84170EC4,841710B8,84171F48,84174D64,84176DA0,841784EC,84178E90,8417E964,8417EE50
0A: 84175B60,84175EF4,841768F4,84176AF0,84176CEC,84176FB4
0F: 841732BC
28: 841748B8,84175E6C,84180F1C
2A: 84171668,8417B058
32: 8416EA90,84170DEC,84170F64
36: 8416D50C
37: 8416A868
3C: 8416D328,8416D7D8,8416E7C4
4B: 84172598
5A: 841703EC
69: 84174F68
```

### Mode 8 / opcode 15: value is encoded pointer byte `+3`

```text
00: 8416BE60,8416F31C,8416F958,84170EDC,84171294,84173538,8417760C,841798F0,84179A40,84179D28,8417A838,8417AA08,8417B37C,8417B500,8417C9A4,8417CC24,8417D0E0,8417D988,8417EF30
02: 8417B890,8417D3F4
05: 8417A6D4
07: 84175C1C
0C: 84171084,8417EE1C
0F: 841732D4
15: 8416D544
1D: 84174DD8
21: 84177300,84177724
22: 84177A4C,84179E64
23: 84179820,84179C70,8417A948
2A: 8416E42C,8417B034
2B: 8416C83C,84177814
2E: 84175910
2F: 8416FC94
32: 84170E18,84170F90
37: 8416E4FC,8417CB30
3A: 8416EDDC
3C: 8416E7A8
40: 8416CC38,8417121C
7C: 8416D330,8416D7E0
```

Modes 4 and 6 have no unique pointer families because their opcode counts are
zero, not because their constructor ranges are absent.

## Proven versus unresolved fields

### Proven

* Native command records are 8 bytes for all five target opcodes.
* The command word at record `+4` is passed to `0x80003240`; that function's
  return pointer becomes scheduler slot `+0`.
* Scheduler slots are 12 bytes, 64 deep, with the countdown/mode/active
  offsets listed above.
* Constructor delay source is resolved-object byte `+3` for modes 2/4/8 and
  byte `+1` for modes 5/6.
* All target constructors set reload `+5=0`, state `+7=1`, and the mode byte.
* Mode 2 consumes resolved-object byte `+3` as a visual-allocation loop bound.
* Mode-2 visual setup reads resolved-object word `+4` as flags and pointer
  graph data at `+12` through the motion/geometry helpers.
* Mode 4, mode 5/6, and mode 8 have the local visual initialization ranges
  and side allocations documented above.
* Visual draw dispatch uses visual `+0x7C`, active `+0x98`, and the table at
  `0x84188BB0`; visual release is `0x8410488C -> 0x84100350`.

### Unresolved

* The body and ABI of external resolver `0x80003240`.
* Whether the encoded command pointer equals the resolver return pointer.
* The complete resolved-object sizes and all fields beyond the accesses cited
  above; the minimum mode-2 structure is at least 16 bytes because it reads
  `+12`, and the visual flag word at `+4` is proven.
* The precise work performed by external calls reached from the local
  update/draw wrappers, and any linked-overlay callees they use.
* Semantic names for global `0x84190194`, visual flag masks, visual fields,
  float constants, and the external allocation calls.
* Battler/camera attachment semantics and any draw-time resource binding.
* Native-object visual lifetime rules after scheduler release.

## Decoder/runtime implementation plan

1. Preserve each 8-byte command as `{opcode, commandPointer, raw}`.  Do not
   call the command pointer a descriptor yet.
2. Add a native-object resolver interface that receives the command pointer
   and returns either `{pointer, raw/fields}` or an explicit unresolved
   diagnostic.  The initial implementation may use an injected ROM resolver;
   it must not assume identity for `0x80003240`.
3. Decode a mode-specific header view with `delaySource = +3` for modes 2/4/8
   and `delaySource = +1` for modes 5/6.  Set scheduler reload to zero and
   expose the untouched `+10..+11` bytes rather than inventing repeats.
4. Model the scheduler as a 64-slot persistent object with countdown/current
   age/state/active/mode fields.  Invoke exactly one registered mode update
   callback at the authored countdown boundary, then apply the `0xFF` versus
   age-equality rules from `0x84107C64..0x84107CB0`.
5. Register callback families by mode.  Mode 5 and mode 6 may share the local
   initializer implementation, but keep their external update-table IDs
   distinct.  Mode 2 must expose its authored count loop and pointer-graph
   helpers; modes 4/5/6/8 should retain unresolved draw/resource operations.
6. Keep scheduler objects and 300-entry visual objects as separate runtime
   entities.  A draw packet should be produced only after the visual object
   exists and should carry mode, resolved pointer identity, flags, and
   unsupported-callback diagnostics.
7. Implement draw/release adapters around the raw table IDs.  Until linked
   overlay bodies are available, emit explicit `unsupported-native-draw` and
   retain the object; never synthesize geometry by move type.
8. Add ROM-wide audit assertions for the counts and pointer-family inventory
   above.  Add synthetic mode 4 and mode 6 constructor fixtures even though
   retail program coverage is zero; those fixtures should exercise the handler
   schemas without claiming a ROM program instance.

## ROM-backed golden fixtures

These are small, stable records suitable for the decoder audit:

| mode | program | record address | command pointer | bytes at pointer (first 32 bytes) | expected constructor timing source |
| ---: | ---: | ---: | ---: | --- | --- |
| `2` | `98` | `0x84173DA4` | `0x8416A3E0` | `00 00 00 23 84 16 A3 D8 00 00 00 14 84 16 A3 D8 ...` | byte `+3 = 0x23`; mode-2 visual loop bound also reads byte `+3` |
| `5` | `328` | `0x841788B8` | `0x84178894` | `00 02 00 00 84 17 88 88 01 00 00 00 08 00 00 00 ...` | byte `+1 = 0x02` |
| `8` | `299` | `0x8416C880` | `0x8416C83C` | `00 00 00 2B 84 16 A3 90 00 00 00 0F 00 3C 00 4C ...` | byte `+3 = 0x2B` |
| `4` | — | — | — | no opcode-6 records in programs `0..394` | handler-only synthetic fixture |
| `6` | — | — | — | no opcode-13 records in programs `0..394` | handler-only synthetic fixture |

For the mode-2 fixture, the pointer at object `+12` is `0x8416A3D8`, which is
consumed by `0x8410679C`.  For mode 5, object `+4` is `0x84178888`; for mode
8, object `+4` is `0x8416A390`.  These are ROM bytes/pointers only; their
resource semantics remain unresolved.

## Acceptance

No source files outside this report were changed.  The final report was
checked with `git diff --check`.
