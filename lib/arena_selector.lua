-- Pure Gen 2 battle-context to Stadium 2 field resolver.  This module owns no
-- engine objects and consumes only the data copied from public mod events and
-- hooks, so arena selection cannot retain or mutate the live world.
local Selector = {}

local MAP_ARENAS = {
  VIOLET_GYM=0, AZALEA_GYM=1, GOLDENROD_GYM=2, ECRUTEAK_GYM=3,
  OLIVINE_GYM=4, CIANWOOD_GYM=5, MAHOGANY_GYM=6,
  BLACKTHORN_GYM_1F=7, BLACKTHORN_GYM_2F=7,
  WILLS_ROOM=9, KOGAS_ROOM=10, BRUNOS_ROOM=11, KARENS_ROOM=12,
  CHAMPIONS_ROOM=13, LANCES_ROOM=13,
  PEWTER_GYM=14, CERULEAN_GYM=15, VERMILION_GYM=16,
  CELADON_GYM=17, FUCHSIA_GYM=18, SAFFRON_GYM=19,
  SEAFOAM_GYM=20, VIRIDIAN_GYM=21, BATTLE_TOWER_BATTLE_ROOM=26,
}

local TRAINER_ARENAS = {
  FALKNER=0, BUGSY=1, WHITNEY=2, MORTY=3, JASMINE=4, CHUCK=5,
  PRYCE=6, CLAIR=7,
  WILL=9, KOGA=10, BRUNO=11, KAREN=12, CHAMPION=13, LANCE=13,
  BROCK=14, MISTY=15, LT_SURGE=16, LTSURGE=16, ERIKA=17,
  JANINE=18, SABRINA=19, BLAINE=20, BLUE=21, RED=22,
  RIVAL1=29, RIVAL2=29, RIVAL=29,
}

local function key(value)
  return tostring(value or ""):upper():gsub("[^A-Z0-9_]", "")
end

local function rocketMap(mapId)
  return mapId:find("TEAM_ROCKET_BASE",1,true)
    or mapId:find("RADIO_TOWER",1,true)
    or mapId:find("UNDERGROUND_WAREHOUSE",1,true)
end

local function rocketTrainer(trainerId)
  return trainerId:find("GRUNT",1,true)
    or trainerId:find("EXECUTIVE",1,true)
    or trainerId:find("ROCKET",1,true)
end

function Selector.resolve(context)
  local ctx=type(context)=="table" and context or {}
  if tonumber(ctx.generation)~=2 then return nil,"not-gen2" end

  -- battle.started.kind is the engine's authoritative distinction.  Wild
  -- encounters use Stadium 2's two general-purpose fields: the park outdoors
  -- and the indoor field in caves/buildings.  This keeps Silver battles in the
  -- extracted Stadium presentation instead of falling back to the small
  -- classic platforms merely because the opponent has no trainer.
  local battleKind=key(ctx.kind)
  if battleKind=="WILD" then
    if ctx.outside==true then return 28,"wild:outdoor" end
    if ctx.outside==false then return 27,"wild:indoor" end
    return 28,"wild:outdoor-default"
  end
  if battleKind~="TRAINER" then return nil,"unsupported-kind:classic" end

  local mapId=key(ctx.mapId)
  local trainerId=key(ctx.trainerId)
  local mapped=MAP_ARENAS[mapId]
  if mapped~=nil then return mapped,"map:"..mapId end

  if ctx.battleTower==true then return 26,"battle-tower" end
  if trainerId=="RED" or mapId:find("MT_SILVER",1,true) then
    return 22,"mt-silver"
  end
  if rocketMap(mapId) or rocketTrainer(trainerId) then
    return 8,"team-rocket"
  end

  mapped=TRAINER_ARENAS[trainerId]
  if mapped~=nil then return mapped,"trainer:"..trainerId end

  if ctx.outside==true then return 28,"outdoor" end
  if ctx.outside==false then return 27,"indoor" end
  return nil,"unknown:classic"
end

Selector.MAP_ARENAS=MAP_ARENAS
Selector.TRAINER_ARENAS=TRAINER_ARENAS
return Selector
