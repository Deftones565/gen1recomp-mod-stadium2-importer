package.path='./?.lua;./?/init.lua;'..package.path
local E=require('mods.STADIUM2_IMPORTER.lib.battle_environment')
local cases={
 {'grass',{environment='ROUTE',terrain='grass'}},
 {'town',{mapId='PALLET_TOWN'}},
 {'freshwater',{environment='TOWN',mapId='OLIVINE_CITY',terrain='water',waterType='freshwater'}},
 {'grass',{environment='TOWN',terrain='grass'}},
 {'town',{environment='TOWN'}},
 {'cave',{environment='CAVE'}},
 {'cave_water',{environment='CAVE',terrain='water'}},
 {'freshwater',{environment='ROUTE',terrain='surf',mapId='ROUTE_42'}},
 {'ocean',{environment='ROUTE',terrain='water',mapId='ROUTE_40'}},
 {'ocean',{environment='TOWN',battleType='fish',mapId='OLIVINE_CITY'}},
 {'ice_cave',{environment='CAVE',mapId='ICE_PATH_B1F'}},
 {'ice_cave',{environment='CAVE',mapId='SEAFOAM_ISLANDS_B4F'}},
 {'gym',{environment='INDOOR',mapId='VIOLET_GYM'}},
 {'league',{environment='INDOOR',mapId='CHAMPIONS_ROOM'}},
 {'industrial',{environment='DUNGEON',mapId='TEAM_ROCKET_BASE_B2F'}},
 {'ruins',{environment='CAVE',mapId='RUINS_OF_ALPH_INNER_CHAMBER'}},
 {'ship',{environment='INDOOR',mapId='FAST_SHIP_1F'}},
 {'mountain',{environment='ROUTE',mapId='ROUTE_45'}},
 {'interior',{environment='INDOOR',mapId='SOME_HOUSE'}},
 {'indoor_water',{environment='INDOOR',terrain='water'}},
 {'unknown',{environment='UNRECOGNIZED',terrain='grass'}},
}
for _,case in ipairs(cases) do
 local id,ctx=case[1],case[2];ctx.generation=2;ctx.kind='wild'
 assert(E.classify(ctx)==id,case[1]..' got '..E.classify(ctx))
 local built=E.catalog[id].module~=nil
 for _,kind in ipairs({'wild','trainer'}) do
  ctx.kind=kind
  local selected=E.select(ctx,'kenney',false)
  assert(selected.mode==(built and 'environment' or 'classic'),id)
  selected=E.select(ctx,'kenney',true)
  assert(selected.mode==(built and 'environment' or 'arena'),id)
  assert(E.select(ctx,'classic',false).mode=='classic')
 end
end
for id in pairs(E.catalog) do
 assert(type(E.catalog[id])=='table')
end
assert(E.select({kind='link',environment='TOWN',generation=2},'kenney',true).mode=='classic')
-- Every location category now has a painted scene; it wins over arena fallback.
local ice=E.select({kind='wild',environment='CAVE',mapId='ICE_PATH_1F',generation=1},'kenney',true)
assert(ice.mode=='environment' and ice.id=='ice_cave')
assert(E.select({kind='wild',environment='CAVE',generation=2},'classic',true).mode=='classic')
local gym=E.select({kind='trainer',environment='INDOOR',mapId='VIOLET_GYM',generation=2},'kenney',true)
assert(gym.mode=='environment' and gym.id=='gym')
-- With Kenney environments off, context arenas still apply.
assert(E.select({kind='trainer',environment='INDOOR',mapId='VIOLET_GYM',generation=2},'classic',true).arena==0)
print('Environment catalog, location precedence, terrain overrides and classic/arena fallback passed')

for id in pairs(E.catalog) do
 local ctx={environment=id,generation=2,kind='wild'}
 assert(E.classify(ctx)==id,'explicit category '..id..' was not registered')
end
print('Every catalog category has an explicit environment classification')

local original={generation=2,kind='wild',mapId='ICE_PATH_1F',environment='CAVE',terrain='water'}
for id in pairs(E.catalog) do if id~='unknown' then
 local s=E.select(original,'classic',false,nil,id)
 assert(s.id==id and s.mode==(E.catalog[id].module and 'environment' or 'classic'),id)
 assert(E.select(original,'classic',true,nil,id).mode==(E.catalog[id].module and 'environment' or 'arena'))
end end
assert(original.environment=='CAVE' and original.terrain=='water','override mutated encounter')
assert(E.select(original,'kenney',false,nil,'automatic').id=='ice_cave')
assert(E.select(original,'classic',false,nil,'invalid').mode=='classic')
for i=0,29 do
 for _,generation in ipairs({1,2}) do
  for _,kind in ipairs({'wild','trainer','link'}) do
   local s=E.select({generation=generation,kind=kind},'classic',false,nil,'town',i)
   assert(s.mode=='arena' and s.arena==i and s.reason=='test-override')
  end
 end
end
for _,invalid in ipairs({-1,30,2.5,'2'}) do
 assert(E.select(original,'classic',false,nil,'town',invalid).mode=='environment')
end
local Importer=require('mods.STADIUM2_IMPORTER.lib.importer')
local values={}
Importer.bind({options={get=function(_,k) return values[k] end}})
assert(Importer.environmentTest()=='automatic' and Importer.arenaTest()==nil)
values.stadium2_environment_test='town';values.stadium2_arena_test=0
assert(Importer.environmentTest()=='town' and Importer.arenaTest()==0)
values.stadium2_environment_test='invalid';values.stadium2_arena_test=99
assert(Importer.environmentTest()=='automatic' and Importer.arenaTest()==nil)
print('Environment overrides, all 30 arena overrides, precedence and invalid settings passed')
