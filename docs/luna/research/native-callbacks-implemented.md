# Native-object callbacks: verified US implementation

This supersedes incorrect constructor/render interpretations in the earlier
native-object audit notes. Evidence is the supported US ROM and fragment79
at the pinned pret commit; unmatched functions were checked in ROM assembly.

All 242 native-object descriptors across the 395 catalog programs use modes
2, 5 or 8. The regression executes every descriptor through its entire
callback lifetime without unsupported diagnostics. Route coverage (including
alternate routes, overlapping between modes): 104 / 89 / 51 moves.

- Mode 2: constructor `841077E8`, update `84100B3C`, global background color
  setter `8410A4F8`. The earlier `841076B8` attribution was incorrect.
- Mode 5: constructor `84107948`, update `84100C68`. Descriptor+4 is the
  shared primary/secondary color controller. Primary goes through
  `8003F454` to model+A0, then `8003BE5C` / `8003DAF0` / `8003CFB8` to the
  RDP fog/blend color. Secondary alpha goes through `8003F4DC` to model+1D
  opacity. Descriptor+2 sets visual flags 0x280 at the specified age;
  the visual expires at the controller period. Model writes persist.
- Mode 8: constructor `841078B8`, update `84100B3C`. The call to `81100020`
  sets flags at visual+14; **0x7028 is a flag mask, not an allocation size**.
  `0x43200000` is **160**, not 40. The origin is (160,120). Flags select
  the 2D pass in `84103478`; `841032F0` reads `8418CB88`, export90 in the
  resource table. That actual ROM export contains the untextured 320x240
  screen quad. Secondary RGBA changes over time; the visual disappears at
  its controller period. It does not change the background-fill color.

`84100688` selects half-open key intervals; duplicate key ages are legal,
and the rightmost key wins at an exact duplicate age. The decoder accepts
nondecreasing keys and the evaluator preserves this jump behavior.

The shared Player publishes model colors during scene geometry and defers
screen draws until after battlers, using a 320x240 orthographic projection
and no depth writes. Both real battles and the Koffing/Croconaw viewer use
this path. Release clears all persistent model/screen/background state.

Validation: native ROM regression, scheduler/color regression, player
render-handoff regression, full strict-ROM worker gate, standalone renderer
and GPU stub checks. No screenshot/visual parity claim is made.

Modes 4 and 6 have no descriptors in any of the 395 supported ROM programs;
their injected-callback APIs and unsupported diagnostics remain. This work
does not implement the separate lifecycle callback families or claim full
battle-animation parity. Model-target override is `context.nativeModelSide`;
the default corresponds to the source model passed to `841086F0`, or the
target model selected by the alternate entry point `8410874C`.
