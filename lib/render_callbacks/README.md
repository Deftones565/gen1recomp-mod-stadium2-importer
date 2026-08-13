# Render callback families

This directory owns handlers whose model command runs during Stadium 2's
render lifecycle rather than ordinary static display-list extraction.

- `phase5_geometry.lua` decodes callback `0x81000140` through the shared
  `func_81001F14`/`func_810024E0` ABI. It resolves callback-owned textures and
  optional primitive/environment colors into the same per-site state consumed
  by the renderer. Species such as Misdreavus share this implementation; do not
  add species-specific texture substitutions for members of this family.

The full-ROM render parity audit requires every phase-5 queue entry to resolve
to a texture or material. The model-completeness audit additionally locks
Misdreavus to eight primitives, 686 triangles, and six routes split into four
texture-driven and two material-driven sites. It also verifies that static
`0x81000140` items are state-only and own following geometry; their arguments
must never be treated as broad display-list pointer tables.

The same is true when item offset `+4` is populated: `func_810024E0` uses that
controller to derive dynamic render state and still emits no model geometry.
All `0x81000140` geometry therefore comes from the following source draw.
