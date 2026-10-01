# Battle placement audit: position, height, scale, facing (2026-10-01)

Sources: US asm (pret `c0e10f2`) for 8411EFE4, 84112704, 84112EDC,
8411BB04, 8411BCC8; fork C `1b6dc17` for 84112EDC / 84112FD0 / 8411293C;
the supported US ROM (battle profiles at 0x49DA60, fragment 79 data);
the importer's model packs for the model floors. Read-only audit; the
port is unchanged by this note. Matches the assembly by reading.

Status (same day, after the audit): Y and Steelix are fixed in the port
(`Scene.nativeOriginHeight`, `Scene:modelMatrix` arena and custom-scene
branches; `StadiumBattleLayout` 208 = 325). The classic scene keeps its own
grounding. Test: stadium2_gen2_scene_test.lua (profile height 100, Steelix
325). Viewer check: Koffing (profile 65) floats above its shadow. Not yet
seen in game.

## Native rule

84112EDC (model load) runs 84112704, which copies the species' battle
profile (0x30 bytes, 0x49DA60 + (species - 1) * 0x30) into the actor:
+0x04 -> +0x64C (body height), +0x08 -> +0x650, +0x0C -> +0x654,
+0x10/+0x14/+0x18 -> +0x634/+0x638/+0x63C, +0x14 -> +0x648 (centre),
+0x1C -> +0x640, +0x20 -> +0x644. Then 8411EFE4 places the model:

- facing: 80035A68(+0x1E, 0, +-0x4000, 0): +0x4000 for battler 0 (the
  player's), -0x4000 for the other.
- X (+0x24): -/+150, or by species (+0x1A): Venusaur (3) 185, Onix (95)
  225, Gyarados (130) 200, Steelix (208) D_84189810 / D_84189814 =
  -325 / +325 (ROM data), Lugia (249) 200, Ho-Oh (250) 185.
- Y (+0x28) = +0x650 = profile +0x08: the model's origin height.
- Z (+0x2C) = 0.
- Scale: none of these write +0x30..+0x38; the battler keeps 1.0
  (Minimize 84122998 and Meditate 84122A78 also start from it).
- Send-out (8411BB04 / 8411BCC8): no scale change; model alpha (+0x1D) is
  0 and the send-out effect's opacity track (0x122, P311) shows the
  Pokemon at its frame 97.

## Port

- facing, Z, scale 1.0 (times the arena scale 0.05): match.
- X: matches, except Steelix: `StadiumBattleLayout` uses 0 ("overlay
  storage after relocOffset 0x8C950 is zeroed"), but D_84189810 is at
  fragment offset 0x89810, before relocOffset, and holds -325 / +325.
  Steelix stands in the middle of the field instead of at its slot.
- Y: `Scene:modelMatrix` grounds every model by its lowest vertex
  (`metrics.floor`) instead of placing its origin at profile +0x08. The
  STADIUM camera (`StadiumCamera:sync`) does use +0x650, so its shots aim
  at the native height while the model is drawn on the floor. 22 species
  have a non-zero profile height and 54 species end up at least 2 Stadium
  units (0.1 world units) away from the native height; the largest are
  flying or floating Pokemon (list below).
- Send-out: the port's 0.65 s grow (Actor:entrance) is not native; with
  battle effects on it finishes while the send-out keeps the model
  invisible, so it shows only with effects off.

## Species off the native height (lowest point, Stadium units)

`ground` is profile +0x08, `floor` the model's lowest point relative to its
origin; native lowest point = ground + floor, the port's = 0.

```
|ground+floor| >= 2 units: 54 species
  #022 ground 100.0 floor -13.3 -> native lowest point 86.7 (height 49.0, model.floor)
  #169 ground 101.0 floor -23.5 -> native lowest point 77.5 (height 101.3, model.floor)
  #092 ground 110.0 floor -32.5 -> native lowest point 77.5 (height 65.0, model.floor)
  #041 ground 0.0 floor 72.8 -> native lowest point 72.8 (height 24.1, model.floor)
  #142 ground 91.0 floor -26.1 -> native lowest point 64.9 (height 138.5, model.floor)
  #093 ground 105.0 floor -45.3 -> native lowest point 59.7 (height 87.1, model.floor)
  #087 ground 64.0 floor -6.8 -> native lowest point 57.2 (height 13.5, model.floor)
  #226 ground 0.0 floor 56.2 -> native lowest point 56.2 (height 94.2, model.floor)
  #071 ground 85.0 floor -34.9 -> native lowest point 50.1 (height 121.7, model.floor)
  #130 ground 0.0 floor 49.0 -> native lowest point 49.0 (height 147.2, model.floor)
  #012 ground 65.0 floor -16.8 -> native lowest point 48.2 (height 50.4, model.floor)
  #109 ground 65.0 floor -19.5 -> native lowest point 45.5 (height 40.2, model.floor)
  #021 ground 50.0 floor -5.6 -> native lowest point 44.4 (height 16.5, model.floor)
  #049 ground 65.0 floor -21.9 -> native lowest point 43.1 (height 73.1, model.floor)
  #193 ground 0.0 floor 42.8 -> native lowest point 42.8 (height 34.4, model.floor)
  #116 ground 50.0 floor -7.9 -> native lowest point 42.1 (height 21.1, model.floor)
  #117 ground 66.0 floor -27.8 -> native lowest point 38.2 (height 61.8, model.floor)
  #110 ground 70.0 floor -32.9 -> native lowest point 37.1 (height 69.5, model.floor)
  #170 ground 0.0 floor 37.1 -> native lowest point 37.1 (height 33.4, model.floor)
  #171 ground 0.0 floor 36.1 -> native lowest point 36.1 (height 41.5, model.floor)
  #015 ground 65.0 floor -30.1 -> native lowest point 34.9 (height 62.9, model.floor)
  #074 ground 0.0 floor 34.1 -> native lowest point 34.1 (height 28.3, model.floor)
  #151 ground 43.0 floor -9.7 -> native lowest point 33.3 (height 21.4, model.floor)
  #145 ground 81.0 floor -50.3 -> native lowest point 30.7 (height 102.5, model.floor)
  #205 ground 0.0 floor 30.7 -> native lowest point 30.7 (height 58.6, model.floor)
  #081 ground 0.0 floor 30.6 -> native lowest point 30.6 (height 16.7, model.floor)
  #119 ground 51.0 floor -21.1 -> native lowest point 29.9 (height 44.5, model.floor)
  #233 ground 0.0 floor 28.5 -> native lowest point 28.5 (height 30.2, model.floor)
  #211 ground 0.0 floor 26.6 -> native lowest point 26.6 (height 37.1, model.floor)
  #230 ground 0.0 floor 23.3 -> native lowest point 23.3 (height 85.0, model.floor)
  #091 ground 0.0 floor 23.0 -> native lowest point 23.0 (height 89.3, model.floor)
  #118 ground 26.0 floor -4.8 -> native lowest point 21.2 (height 16.0, model.floor)
  #073 ground 93.0 floor -72.8 -> native lowest point 20.2 (height 92.0, model.floor)
  #129 ground 0.0 floor -19.1 -> native lowest point -19.1 (height 41.0, model.floor)
  #223 ground 0.0 floor 17.6 -> native lowest point 17.6 (height 47.7, model.floor)
  #070 ground 0.0 floor -17.1 -> native lowest point -17.1 (height 54.2, model.floor)
  #082 ground 42.0 floor -25.2 -> native lowest point 16.8 (height 45.0, model.floor)
  #131 ground 0.0 floor 15.8 -> native lowest point 15.8 (height 141.8, model.floor)
  #200 ground 0.0 floor 15.6 -> native lowest point 15.6 (height 39.1, model.floor)
  #191 ground 0.0 floor 14.9 -> native lowest point 14.9 (height 15.0, model.floor)
  #146 ground 0.0 floor -14.4 -> native lowest point -14.4 (height 131.6, model.floor)
  #072 ground 60.0 floor -46.6 -> native lowest point 13.4 (height 68.3, model.floor)
  #144 ground 0.0 floor -11.2 -> native lowest point -11.2 (height 98.0, model.floor)
  #208 ground 0.0 floor 10.7 -> native lowest point 10.7 (height 198.3, model.floor)
  #137 ground 0.0 floor -10.1 -> native lowest point -10.1 (height 37.7, model.floor)
  #250 ground 0.0 floor -7.1 -> native lowest point -7.1 (height 142.0, model.floor)
  #207 ground 0.0 floor 6.9 -> native lowest point 6.9 (height 58.2, model.floor)
  #018 ground 0.0 floor -3.4 -> native lowest point -3.4 (height 83.7, model.floor)
  #203 ground 0.0 floor -3.3 -> native lowest point -3.3 (height 78.0, model.floor)
  #232 ground 0.0 floor -3.2 -> native lowest point -3.2 (height 58.1, model.floor)
  #095 ground 0.0 floor -2.7 -> native lowest point -2.7 (height 141.4, model.floor)
  #247 ground 0.0 floor -2.6 -> native lowest point -2.6 (height 63.6, model.floor)
  #224 ground 0.0 floor -2.4 -> native lowest point -2.4 (height 47.7, model.floor)
  #048 ground 0.0 floor -2.1 -> native lowest point -2.1 (height 62.2, model.floor)
```

## Open

- Gen 2's picElevation (the host's Fly / Dig pic motion) lifts the model in
  model-height units; Stadium's own Fly / Dig states move the actor
  (camera port: flyUpState / flyRiseFrame). Not compared yet.
- Transform: 8411EFE4 reads the slot species from +0x1A; the port uses the
  shown Pokemon's species. Not compared yet.
