# Lifecycle rendering trace: family 4

## Result

Family 4 is reachable in the supported US Stadium 2 ROM through the primary
move table for move IDs 20, 35, and 132.  The alternate bank routes the same
three moves to family 23.  This pass resolves family 4's persistent state,
timer gate, draw-wrapper command, per-slot draw loop, and the nested display
list builder.  It does **not** resolve the archive/model owner or the native
placement ABI.  Therefore the end-to-end renderable model is still blocked;
the safe runtime result is exact command evidence plus an explicit unresolved
diagnostic until a main-memory model resolver is injected.

## Sources and address mapping

Behavioral evidence is from the supported `Pokemon Stadium 2 (USA).z64` ROM
(MD5 `1561c75d11cedf356a8ddb1a4a5f9d5d`) and Fragment 79.  Fragment 79 is
loaded at ROM offset `0x36F890` and VRAM `0x84100000`; for an instruction
address `A`, the extraction offset is:

```text
0x36F890 + (A - 0x84100000)
```

All addresses below are VRAM addresses.  No Lua renderer or procedural visual
was used as evidence.

## Reachable callback chain

The family-4 table row is `init=0x84156E58`,
`update=0x84156E8C`, `draw=0x84156EFC`.

### Initialization: `0x84156E58..0x84156E88`

The callback calls, in order:

```text
0x84156BA0     common allocation/reset helper
0x8415C530     reset ten persistent lifecycle slots
0x84156CCC     family-specific setup/spawn helper
```

It clears the signed 16-bit family counter at `0x841A4D4A`.  The common reset
uses `*(u32 *)0x84187530 + 968` as the slot-array base, ten slots at stride
`1512` (`0x5E8`), and twenty subrecords per slot at stride `72` (`0x48`).
Each slot's `+2` handle is initialized from `0x84169BA8`; this handle must be
preserved as raw evidence, not interpreted as a resource ID.

`0x84156CCC` calls `0x841568A0` and `0x841568C0`, computes component-wise
differences between their returned vectors, and passes three stack vectors to
external callback `0x80070C14`.  The six resulting values are copied to the
caller-provided output pointers.  The vector arithmetic is proven, but the
callback's coordinate/placement contract is not.

### Update: `0x84156E8C..0x84156EF8`

The callback increments `*(s16 *)0x841A4D4A`.  While the counter is in the
inclusive range 120 through 180, it calls `0x84156CCC` only when
`counter % 7 == 0`.  It then always calls `0x8415DAE4`.

At counter 181 and above, the callback passes the `-1` sentinel through its
local branch, but the helper's owner/status interpretation is outside this
callback.  Do not treat the family as expired without the caller-level
termination contract.

### Draw wrapper: `0x84156EFC..0x84156F4C`

The wrapper appends exactly one eight-byte command record at the global cursor
`*(u32 *)0x800D0510`:

```text
*(u32 *)(cursor + 0) = 0xDA380003
*(u32 *)(cursor + 4) = 0x841A4D08
cursor = 0x8415DBBC(cursor)
*(u32 *)0x800D0510 = cursor
```

This proves the outer command packet and its pointer.  It does not prove that
`0x841A4D08` is an archive resource, model descriptor, or portable geometry.

## Per-slot draw and nested display-list evidence

`0x8415DBBC` iterates the same ten slots.  For an active slot (`lh +0 == 1`),
it increments age at `+4`, compares age with threshold `+6`, and either clears
the slot on expiry or calls `0x8415D4C4(slot)`.  Expired slots with subtype
`lh +8 == 5` suppress that call.  Every iteration calls
`0x84169DBC(lh slot+2)`.  The helper returns `0` when at least one non-expired
slot was processed and `-1` otherwise.

`0x8415D4C4` calls `0x84109780(&sp+48)`, dispatches the slot's subtype
(`lhu slot+8`, jump table at `0x8419C698`, cases 0 through 5), and updates the
twenty `0x48`-stride subrecords.  The subtype kernels call external math and
random helpers, but do not expose an archive/model ID.

The strongest inner draw evidence is in `0x84169DBC` (ROM offset `0x3D964C`).
It consumes a slot handle/record and vector-like values, allocates 64 bytes via
`0x80006DEC`, calls `0x8007CFF0` twice, and emits this nested F3DEX2 display
list:

```text
0xDA380002, <allocated 64-byte pointer>
0xFA000000, -56
0xDE000000, 0x84198690
0xD8380002, 64
```

The pointer `0x84198690` is a proven display-list segment pointer in the
native command stream.  Its owning resource/model table is not identified.
Likewise, `0x84169BA8` is proven to provide a slot handle, but its allocator
table and record ownership remain unresolved.

`0x84109780` obtains actor/context data through `0x8411E21C`,
`0x8003C9B8`, `0x8411DCCC`, and `0x84109630`.  Existing attachment research
establishes that these routines carry actor position and side/lane-like data,
but their exact structure and placement ABI are not proven here.

## Implementation-ready resolver fixture

The lifecycle packet builder must be given a resolver only when the caller has
independently proven the model/geometry.  It accepts
`resolveModel(instance, evidence, context)` and requires `proven=true` plus
one of `model`, `geometry`, `modelId`, or `shapeId`:

```lua
local function resolveFamily4Model(instance, evidence, context)
  if evidence.familyId ~= 4 then
    return {proven = false, reason = "family-not-supported"}
  end

  local models = context.lifecycleModels
  local origins = context.lifecycleOrigins
  local model = models and models[4]
  local origin = origins and origins[evidence.instanceId]
  if not model or not origin or origin.resolved ~= true then
    return {
      proven = false,
      reason = "native-model-or-placement-unresolved",
    }
  end

  return {
    proven = true,
    model = model.model,
    geometry = model.geometry,
    modelId = model.modelId,
    shapeId = model.shapeId,
    placement = origin,
    command = evidence.command,
    pointer = evidence.pointer,
    nestedDisplayList = evidence.nestedDisplayList,
  }
end
```

In production, the resolver must reject absent or unproven fields rather than
choosing a procedural shape.  The packet should preserve `familyId=4`, stable
`instanceId`, `effectId`, `programId`, signed counter, frame, source/target
context, outer command/pointer, draw-helper address, and the raw slot handle.
The nested display-list words may be retained as evidence, but are not by
themselves renderable geometry.

## Exact blockers

The following are the remaining high-impact boundaries for family 4 parity:

1. Producer/owner and semantic type of `0x841A4D08`.
2. Owner/resource mapping and geometry represented by `0x84198690`.
3. Allocator/table and record ownership behind `0x84169BA8`.
4. Coordinate and vector contract of setup callback `0x80070C14`.
5. Actor source/placement ABI across `0x84109780`, `0x8411DCCC`,
   `0x8411E21C`, `0x8003C9B8`, and `0x84109630`.
6. Subtype initialization and meaning of jump-table entries at `0x8419C698`.
7. Caller-level interpretation of `0x8415DAE4` status and the family-4
   counter sentinel at 181+.

Until those owners are resolved, the correct parity implementation is an
evidence packet plus `lifecycle-model-unresolved` (or a resolver error), with
no guessed side, target, camera, scale, model, or procedural fallback.

## Acceptance fixture

An exact fixture can assert the following without fabricating visuals:

```text
move 20/35/132, primary -> family 4
counter address      -> 0x841A4D4A, signed 16-bit
draw command         -> 0xDA380003 / 0x841A4D08
draw helper          -> 0x8415DBBC
slot count/stride    -> 10 / 0x5E8
nested allocation    -> 64 bytes via 0x80006DEC
nested command       -> DA380002, FA000000(-56), DE000000(84198690), D8380002(64)
unresolved result    -> explicit diagnostic unless injected resolver proves model + placement
```

This is a complete trace of reachable family-4 lifecycle state and exact
command production, but not an end-to-end model/resource resolution.  No Lua
files were changed in this research pass.
