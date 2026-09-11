package.path='./?.lua;./?/init.lua;'..package.path
local L=require('mods.STADIUM2_IMPORTER.lib.battle_freshwater')
assert(L.matches({environment='ROUTE',kind='wild',terrain='water'}))
assert(L.matches({environment='TOWN',kind='wild',battleType='fish'}))
assert(L.matches({environment='ROUTE',kind='trainer',terrain='surf'}))
for _,ctx in ipairs({{environment='CAVE',kind='wild',terrain='water'},
 {environment='ROUTE',kind='wild',terrain='grass'},
 {environment='ROUTE',kind='wild',terrain='water',waterType='ocean'}, {}}) do assert(not L.matches(ctx)) end
math.randomseed(14);local expected=math.random();math.randomseed(14)
local vs=L.vertices();assert(math.random()==expected)
assert(#vs%3==0 and #vs/3<65000)
for _,v in ipairs(vs) do
 assert(#v==10)
 for _,n in ipairs(v) do assert(n==n and math.abs(n)<2000) end
end
L.release()
print('Freshwater routing, geometry and RNG isolation passed: '..#vs/3)
