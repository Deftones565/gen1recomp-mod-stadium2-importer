-- Audited from the four species-indexed jump tables in Stadium 2 fragment 26.
-- Addresses are the stable identity of shared behavior; species data only
-- describes geometry ownership and invocation layout.
local Manifest = {
  descriptor = 0x81000070,
  tableBases = {
    initialize = 0x810061D0, spawn = 0x810062F4,
    render = 0x81006410, update = 0x81006528,
  },
  species = {
    [77] = { name = "Ponyta", routes = { initialize=0x81004190, spawn=0x810047E0, render=0x81004D44, update=0x8100522C }, ownership="exclusive-card", emitters="carrier-skin" },
    [92] = { name = "Gastly", routes = { initialize=0x8100448C, spawn=0x810047D0, render=0x81004B48, update=0x81005198 }, ownership="inherited-model", emitters="record-bone" },
    [109] = { name = "Koffing", routes = { initialize=0x8100404C, spawn=0x81004620, render=0x81004A38, update=0x8100512C }, ownership="exclusive-card", emitters="carrier-skin" },
    [110] = { name = "Weezing", routes = { initialize=0x8100404C, spawn=0x81004620, render=0x81004A38, update=0x8100512C }, ownership="exclusive-card", emitters="carrier-skin" },
    [134] = { name = "Vaporeon", routes = { initialize=0x810043D8, spawn=0x810047A4, render=0x81004E50, update=0x8100537C }, ownership="mixed-card", carrierPrimitives={4}, emitters="record-bone" },
    [144] = { name = "Articuno", routes = { initialize=0x81004324, spawn=0x81004778, render=0x81004E50, update=0x810052F8 }, ownership="mixed-card", carrierPrimitives={16}, emitters="carrier-skin" },
    [146] = { name = "Moltres", routes = { initialize=0x81004070, spawn=0x8100474C, render=0x81004D44, update=0x810051C0 }, ownership="exclusive-card", emitters="carrier-skin" },
  },
}

function Manifest.profile(species)
  return Manifest.species[math.floor(tonumber(species) or -1)]
end

return Manifest
