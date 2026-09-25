-- One pure classification policy shared by scene construction and rendering.
-- Classifying a location never loads its geometry or allocates GPU resources.
local E={}
E.catalog={
 grass={module='battle_nature'},cave={module='battle_cave'},
 freshwater={module='battle_freshwater'},town={module='battle_town'},
 ocean={},mountain={},ice_cave={},interior={},industrial={},
 ruins={},ship={},gym={},league={},cave_water={},indoor_water={},unknown={},
}
local function key(v) return tostring(v or ''):upper():gsub('[^A-Z0-9]','_') end
local aliases={GRASS='grass',WOODLAND='grass',FOREST='grass',PARK='grass',
 CAVE='cave',TUNNEL='cave',DUNGEON='interior',TOWN='town',CITY='town',ROAD='town',
 LAKE='freshwater',RIVER='freshwater',POND='freshwater',FRESHWATER='freshwater',
 OCEAN='ocean',SEA='ocean',COAST='ocean',BEACH='ocean',MOUNTAIN='mountain',
 CAVE_WATER='cave_water',INDOOR_WATER='indoor_water',
 ICE='ice_cave',ICE_CAVE='ice_cave',INDOOR='interior',INTERIOR='interior',GATE='interior',
 INDUSTRIAL='industrial',FACTORY='industrial',RUINS='ruins',TOWER='ruins',
 SHIP='ship',DOCK='ship',GYM='gym',DOJO='gym',LEAGUE='league',BATTLE_TOWER='league'}
local towns={PALLET_TOWN=true,VIRIDIAN_CITY=true,PEWTER_CITY=true,CERULEAN_CITY=true,
 VERMILION_CITY=true,LAVENDER_TOWN=true,CELADON_CITY=true,FUCHSIA_CITY=true,
 SAFFRON_CITY=true,CINNABAR_ISLAND=true,NEW_BARK_TOWN=true,CHERRYGROVE_CITY=true,
 VIOLET_CITY=true,AZALEA_TOWN=true,GOLDENROD_CITY=true,ECRUTEAK_CITY=true,
 OLIVINE_CITY=true,CIANWOOD_CITY=true,MAHOGANY_TOWN=true,BLACKTHORN_CITY=true}
local function contains(s,parts)
 for _,p in ipairs(parts) do if s:find(p,1,true) then return true end end
 return false
end
function E.classify(ctx,env)
 ctx=ctx or {};env=env or {}
 local map=key(ctx.mapId);local terrain=key(ctx.terrain);local broad=key(ctx.environment or env.environment)
 local water=terrain=='WATER' or terrain=='SURF' or contains(key(ctx.battleType),{'FISH'})
 local category
 if broad=='' and map:match('^ROUTE_?%d+$') then broad='ROUTE' end
 if broad=='' and towns[map] then broad='TOWN' end
 -- Specific interiors and special biomes precede broad CAVE/ROUTE map headers.
 if ctx.battleTower or contains(map,{'BATTLE_TOWER','CHAMPION','LANCES_ROOM','WILLS_ROOM','KOGAS_ROOM','BRUNOS_ROOM','KARENS_ROOM','LORELEIS_ROOM','AGATHAS_ROOM'}) then category='league'
 elseif contains(map,{'_GYM','DOJO'}) then category='gym'
 elseif contains(map,{'ICE_PATH','SEAFOAM_ISLAND','ICE_CAVE'}) then category='ice_cave'
 elseif contains(map,{'FAST_SHIP','SS_ANNE','S_S_ANNE','_PORT','_DOCK'}) then category='ship'
 elseif contains(map,{'ROCKET','SILPH','POWER_PLANT','WAREHOUSE','RADIO_TOWER','POKEMON_MANSION'}) then category='industrial'
 elseif contains(map,{'SPROUT_TOWER','TIN_TOWER','BELL_TOWER','BURNED_TOWER','POKEMON_TOWER','RUINS_OF_ALPH','DRAGONS_DEN'}) then category='ruins'
 elseif contains(map,{'VIRIDIAN_FOREST','ILEX_FOREST','NATIONAL_PARK','SAFARI_ZONE'}) then category='grass'
 elseif map=='LAKE_OF_RAGE' then category='freshwater'
 elseif contains(map,{'MT_MOON','ROCK_TUNNEL','DIGLETTS_CAVE','UNION_CAVE','DARK_CAVE','SLOWPOKE_WELL','WHIRL_ISLAND','VICTORY_ROAD','CERULEAN_CAVE','SILVER_CAVE_ROOM','MT_MORTAR','TOHJO_FALLS'}) then category='cave'
 else category=aliases[broad] end
 if category=='cave' and water then return 'cave_water' end
 if category and category~='grass' and category~='town' and category~='freshwater' and category~='ocean' then
  if water and category=='interior' then return 'indoor_water' end
  return category
 end
 local waterType=key(ctx.waterType)
 local coastal=contains(waterType,{'OCEAN','SEA','SALT'})
  or (waterType=='' and contains(map,{'CIANWOOD','CINNABAR','NEW_BARK','CHERRYGROVE','OLIVINE','VERMILION','PALLET'}))
 local route=tonumber(map:match('^ROUTE_?(%d+)$'))
 if waterType=='' and route and ((route>=19 and route<=21) or (route>=26 and route<=27) or (route>=40 and route<=41)) then coastal=true end
 if category=='ocean' or (water and coastal) then return 'ocean' end
 if water then
  if ctx.outside==false and not category then return 'indoor_water' end
  if category=='town' or category=='grass' or category=='freshwater' or broad=='ROUTE' then return 'freshwater' end
  return 'unknown'
 end
 if category=='town' and terrain=='GRASS' then return 'grass' end
 if category then return category end
 if broad=='ROUTE' then
  if contains(map,{'SILVER','MOUNTAIN'}) or route==45 or route==46 then return 'mountain' end
  return 'grass'
 end
 return 'unknown'
end
function E.resolve(ctx,env,test)
 local forced=type(test)=='string' and test~='unknown' and E.catalog[test]~=nil
 local id=forced and test or E.classify(ctx,env)
 local kind=key(ctx and ctx.kind)
 if not forced and kind~='WILD' and kind~='TRAINER' then return nil,id end
 local name=E.catalog[id].module
 return name and require('mods.STADIUM2_IMPORTER.lib.'..name) or nil,id
end
-- Arena options retain their existing policy when custom environments are off.
-- With automatic environments on, unsupported wild encounters may use arenas too.
function E.select(ctx,style,arenas,env,test,arenaTest)
 if type(arenaTest)=='number' and arenaTest%1==0 and arenaTest>=0
   and arenaTest<require('mods.STADIUM2_IMPORTER.lib.layout').STADIUM_MODEL_TABLE_RECORDS then
  return {mode='arena',arena=arenaTest,reason='test-override',id='arena_test'}
 end
 local forced=type(test)=='string' and test~='unknown' and E.catalog[test]~=nil
 if forced then style='kenney' end
 local scene,id=E.resolve(ctx,env,test)
 if style=='kenney' and scene then return {mode='environment',scene=scene,id=id} end
 if arenas then
  local arena,reason=require('mods.STADIUM2_IMPORTER.lib.arena_selector').resolve(ctx,
   style=='kenney' and {environmentFallback=true} or nil)
  if arena~=nil then return {mode='arena',arena=arena,reason=reason,id=id} end
 end
 return {mode='classic',id=id}
end
return E
