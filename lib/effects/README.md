# Model callback effects

Fragment 26 callback handling is split by responsibility:

- `../handler_registry.lua` is the complete descriptor-to-family catalogue.
- `dynamic_object_manifest.lua` maps each `0x81000070` species to its audited
  initialize, spawn, render, and update ASM routes plus geometry ownership.
- `dynamic_object.lua` implements reusable lifecycle strategies keyed by those
  route addresses and composes per-species profiles at runtime.
- `../effect_renderer.lua` converts effect state into renderer-neutral
  billboard geometry, materials, and render packets.

Do not select behavior from a species-only conditional or from descriptor
`0x81000070` alone. Species sharing is stage-by-stage, and a callback can own
exclusive billboard cards or be inherited by ordinary body geometry. New
routes must first be added to the ROM-backed dynamic-object route audit.
