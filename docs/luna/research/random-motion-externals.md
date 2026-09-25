# Fragment 79 random-motion externals

Status: implementation-ready for the scalar helpers and the inline motion
paths below.  The observations here are from the supported Stadium 2 US ROM,
`pret/pokestadiumgs` behavior, and the decoded fragment-27 and fragment-79
US assembly.  No host RNG or visual category is inferred.

## Address and resolver chain

Fragment 79's random scalar wrapper is at `0x84105E9C`.  Its two imported
helpers are in fragment 27:

```
fragment79 0x84105E9C
    a0 = variant, a1 = bound
    -> 0x81100094       (variant == 0)
    -> 0x811000F8       (variant != 0)

fragment27 0x81100094
    -> main 0x8007AFA0   (the mutable PRNG)
```

For an encoded fragment address `p`, main `0x80003240` calls
`0x800024A0` when `0x81000000 <= p < 0x90000000`.  `0x800024A0` performs:

```
slot = ((p & 0x0FF00000) >> 20) - 0x10
entry = 0x800CC630 + slot * 8
base = *(uint32 *)(entry + 0)
resolved = base ? base + (p & 0x000FFFFF) : p
```

Thus `0x81100094` uses slot 1 (`0x800CC638`) and low offset `0x000094`;
`0x84105E9C` uses slot `0x31` (`0x800CC7B8`) and low offset `0x05E9C`.
The table bases are runtime registration values; the ROM does not justify
hard-coding a fragment base in the renderer.

## Exact scalar helpers

The main helper at `0x8007AFA0` reads the 32-bit state at `0x800A1430`,
computes the low 32 bits of `(4*s + 2) * (4*s + 3)`, stores that value
shifted right by two back to the same state, and returns it:

```
prng_next(s) = (uint32)(((uint64)(4*s + 2) * (4*s + 3)) & 0xFFFFFFFF) >> 2
```

The `4*s + k` operations and multiplication are MIPS unsigned 32-bit
operations.  In pseudocode with explicit wrapping:

```
t = u32((u32(4*s) + 2) * (u32(4*s) + 3))
s' = t >> 2
return s'
```

`0x81100094` then reads the mutable main global at `0x80138C00`, adds it to
the PRNG result modulo 32 bits, divides that sum by 10 with `divu`, and takes
the remainder after dividing the quotient by the caller's bound.  Its exact
unsigned result is:

```
R(n) = 0                                      if n == 0
     = (floor(u32(prng_next(s) + g) / 10) mod n) otherwise
```

where `g = *(uint32 *)0x80138C00`, and `n` is the raw unsigned register
value.  For positive `n`, `R(n)` is in `[0, n-1]`.  The helper mutates
`0x800A1430`; it does not use the host battle RNG.

`0x811000F8` saves the original bound `n`, calls `R(2*n)`, and subtracts
the original bound using 32-bit `subu`:

```
C(n) = R(u32(2*n)) - n
```

For a positive bound that does not overflow the doubled argument, the
mathematical range is `[-n, n-1]`.  Both globals are runtime state; their
initialization and synchronization with the game are not recoverable from
these helper bodies and remain an integration dependency.

### Fragment-79 wrapper semantics

`0x84105E9C` first masks `a1` to 16 bits.  A zero bound returns zero without
advancing the PRNG.  A masked bound of `0xFFFF` is replaced with `0x10000`.
The signed 16-bit `a0` selects the helper: zero calls `R`, and any nonzero
value calls `C`.  The returned value is then explicitly narrowed to signed
16-bit (`sll v0,16; sra v0,16`).  Therefore a caller requesting `R(0x10000)`
can observe values `0..65535` only after the wrapper's signed narrowing (the
upper half appears negative), while `C(0x10000)` produces the centered raw
range `[-65536,65535]` before the same narrowing.

Implementation fixtures, with state `s=0` and global offset `g=0`:

```
prng_next(0) = 1
R(10)        = 0       (quotient floor(1/10) is 0)
next state   = 1
prng_next(1) = 10
R(10)        = 1       (if called next)
R(0)         = 0       (and state is not advanced)
C(1)         = R(2)-1, so its result is either -1 or 0
```

The `R(10)` examples assume each call uses the stated current state and
`g=0`; they are suitable for testing a stateful injected implementation.

## Trig table mapping

Fragment 27 helper `0x811001A0` and fragment 79's inline modes use two main
segment float tables:

```
TA(i) = *(float *)(0x80087E50 + (i * 4))
TB(i) = *(float *)(0x80088E50 + (i * 4))
i     = (uint16(angle) >> 4)       // 0..4095 for a halfword angle
```

The helper's exact output for input components `(x, y, z)` and angle index
`i` is, in single-precision operation order:

```
out.x = x * TB(i) + z * TA(i)
out.y = y
out.z = -x * TA(i) + z * TB(i)
```

The first table's ROM samples are `0.0`, `0.0015339801`, and
`0.0030679568`, consistent with `sin(pi*i/2048)`.  That identifies `TA` as
the sine-like table. TB is the ROM-backed window 1024 entries after TA.
The signed addiu address was corrected in the subsequent
[common motion audit](common-motion-next.md); use its byte ranges and evidence.

## Modes 0, 1, 2, 3, and 5

The mode routine receives a destination vector, a mode, bounds at stack
`+0x28/+0x2A/+0x2C`, and a context pointer at stack `+0x30`.  Context angles
are unsigned halfwords at `+0x6A`, `+0x6C`, and `+0x6E`.  Define:

```
iP = context[0x6A] >> 4;  iQ = context[0x6C] >> 4;  iR = context[0x6E] >> 4
FP = float(MIPS_unsigned_to_float(u32(random + offset)))
```

For `FP`, the code executes `mtc1`, `cvt.s.w`, then, when the integer's sign
bit is set, adds the single-precision constant `4294967296.0`.  This is the
MIPS idiom for converting an unsigned 32-bit integer to a float.  All table
arithmetic below is single precision, and the listed operation grouping
preserves the instruction order.

### Mode 0

For each component independently, call the fragment-79 wrapper with variant
`0` and the corresponding unsigned halfword bound.  Store the resulting
signed-16 value as a float:

```
out.x = float(int16(wrapper(0, lhu(stack+0x28))))
out.y = float(int16(wrapper(0, lhu(stack+0x2A))))
out.z = float(int16(wrapper(0, lhu(stack+0x2C))))
```

### Mode 1

The same three calls use variant `1` (the centered helper):

```
out.x = float(int16(wrapper(1, lhu(stack+0x28))))
out.y = float(int16(wrapper(1, lhu(stack+0x2A))))
out.z = float(int16(wrapper(1, lhu(stack+0x2C))))
```

### Modes 2 and 3

Both modes call `0x81100094` once with `bound = lhu(stack+0x28)`, add
`offset = lhu(stack+0x2A)`, and convert that unsigned sum to `FP`.  They then
read all three context angles.  Let `AP=TA(iP)`, `AQ=TA(iQ)`, `AR=TA(iR)` and
similarly `BP`, `BQ`, `BR` for `TB`.  The recovered instruction sequence is:

```
out.x = FP * (AQ * BP + (AP * BQ) * AR)
out.y = (-FP * AP) * BR
out.z = FP * (BP * BQ - (AR * AP) * AQ)
```

Mode 2 (`0x84106098..0x841061E4`) and mode 3
(`0x841061E8..0x84106334`) emit the same multiplication, add/subtract, and
sign order in the decoded US body.  They are separate control-flow paths,
but there is no proven mode-3 permutation to implement.

### Mode 5

Mode 5 also calls `0x81100094` once with `lhu(stack+0x28)`, adds the unsigned
offset at `stack+0x2A`, and applies the unsigned-to-float correction.  It uses
only `iP`:

```
out.x = FP * TA(iP)
out.y = FP * TB(iP)
out.z = 0.0
```

## Unresolved pieces and boundaries

* The initial/authoritative values and save/restore ownership of globals
  `0x800A1430` and `0x80138C00` are not established by these routines.
  Exact parity needs those values supplied by the runtime or an injected
  state object; substituting host RNG is incorrect.
* TA and TB are decoded from the ROM; older overlay-only caches require the
  new battle_fx_trig special block to supply them.
* Exact IEEE-754 single-precision behavior matters for large unsigned values
  and for every multiply/add/subtract.  A parity implementation should keep
  the MIPS operation order rather than algebraically reassociate the formulas.
* This report covers scalar generation and motion-vector construction only.
  It does not establish object lifetime, callback dispatch, downstream scale,
  or draw-resource semantics.
