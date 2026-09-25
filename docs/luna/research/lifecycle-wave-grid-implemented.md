# Wave-grid lifecycle progress

US ROM and pret revision c0e10f23d90cc4f335b654711f13e53c2c07323b.

Families 9, 10 and 11 now initialize and update persistent 16x16 vertex positions,
amplitude, alpha, counter and termination state. Sources: 8415F0D0/8415F9A0
and 841614E0/84161DAC. These families cover primary routes 95, 103, 173,
45, 48 and 134, plus Sing47 and Perish Song195 through family10.
Initialization, update and drawing are connected to the
battle player and visual viewer. ROM visual parity is not yet certified.

Both wrappers pass 1800, not 25, as initial duration (84157ECC/84158014).
The first controller signal of exactly 1 from 841094EC resets the counter to
zero and selects duration25. Expiry occurs when counter exceeds duration.
The public lifecycle manager accepts this explicit state through
setNativeSignal; no automatic host timing is invented. Alpha rises by10 to
128/80, then falls by12/8 starting at finish counter16. Amplitude starts at
.01/0 and increases by.05 while below1/.25. Native float/double operation
boundaries in radial displacement are retained, with host sin rounded to
float32 (not bit-exact libultra sine).

Snapshot nativeState includes positions and controller state. The draw path
constructs 256 signed-truncated vertices and 450 triangles with alternating
diagonals. Native normal reconstruction normalizes both edges and their cross
product in four neighbor quadrants, adds the first three contributions and
subtracts the fourth, then normalizes the sum. Normals are truncated after
multiplication by120 before reaching the renderer. White ambient light makes
shade RGB white; vertex alpha carries the native fade through both combiner
cycles. G_TEXTURE_GEN uses the changing normals. The native mode omits Z-buffer
testing. A fixed mesh is reused, updated only when the runtime frame changes,
and released on expiry. Existing ribbon rendering is preserved.

The camera-facing placement uses eye/focus and FOV from the current scene,
including the native105/(FOV/30) displacement beyond focus. It uses host float
rotation rather than N64 angle-table quantization and fixed-point matrices.
Degenerate or missing cameras produce placement diagnostics. The presentation
controller's finish signal still requires explicit host integration; without
it the native1800-tick default applies. No screenshot or pixel comparison has
been performed, so camera orientation and texture-generation fidelity remain
visual acceptance items.

The draw texture is export38 for family9 and export36 for families10/11, resolved through each move's loaded resource
bindings, not a static overlay pointer or a shape descriptor. The new
Resources.waveGridTexture reader decodes its32x32 RGBA16 pixels. Resource25
owns the ordinary texture; Snore's resource96 overrides it. Tests validate
eight dispatch routes, these resource bindings, dimensions, independent snapshots,
native finish edge cases and the unsignalled1800-tick duration. Headless renderer
tests cover all three families, mesh creation/reuse, vertex alpha updates, camera
placement and disposal. Full ROM worker checks and renderer regression tests pass.

Family10 sources: init841603A0, disturbance84160250, update84160CD8 and
draw84161018. Initialization sums phase contributions of pi/2 at zero distance
or (pi/2)/distance otherwise: one fixed disturbance at(8,8), then ten pairs of
RNG values modulo16. This consumes twenty calls to the isolated native RNG,
not random values per vertex. Every update samples sin(phase)*.5+1 then adds
.1 to phase. The amplitude state ramps from.01 toward.5 but is not used by
this displacement formula. Lifecycle.new accepts injected random or seed;
the default is an independent instance of the existing ROM RNG. Finish timing
and alpha match family9. Material0x0C184240 disables depth comparison/writes
even though family10 geometry mode0x260005 includes G_ZBUFFER.
