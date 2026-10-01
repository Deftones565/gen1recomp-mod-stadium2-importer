-- Pokemon Stadium 2 (US) fragment 79 battle-model placement.
--
-- The battle overlay writes the model position at 0x8411EFE4 and returns the
-- inward-facing yaw at 0x8411E140. Ordinary species use X = +/-150, Z = 0
-- and yaw = -/+0x4000 binary-angle units. The explicit large-body branches
-- adjust the X slot for the species below. Keep these source-space Stadium
-- units here; callers apply the same ROM-to-world scale as the arena.
local Layout = {}

Layout.DEFAULT_DISTANCE = 150
Layout.SPECIES_DISTANCE = {
  [3] = 185,   -- Venusaur
  [95] = 225,  -- Onix
  [130] = 200, -- Gyarados
  -- Steelix loads its slot from fragment-79 data D_84189810 / D_84189814:
  -- -325 / +325 (US ROM). Corrected 2026-10-01: that data is at fragment
  -- offset 0x89810, before relocOffset (0x8C950), so it is not zeroed.
  [208] = 325,
  [249] = 200, -- Lugia
  [250] = 185, -- Ho-Oh
}

function Layout.distance(species)
  species = math.floor(tonumber(species) or 0)
  return Layout.SPECIES_DISTANCE[species] or Layout.DEFAULT_DISTANCE
end

function Layout.slot(side, species)
  local distance = Layout.distance(species)
  if side == "player" then
    return { -distance, 0, 0 }, math.pi * .5
  end
  return { distance, 0, 0 }, -math.pi * .5
end

return Layout
