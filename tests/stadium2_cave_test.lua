package.path='./?.lua;./?/init.lua;'..package.path
local root='mods.STADIUM2_IMPORTER.lib.'
local Cave=require(root..'battle_cave')
assert(Cave.matches({environment='CAVE',kind='wild',terrain='cave'}))
assert(Cave.matches({environment='CAVE',kind='trainer'}))
for _,ctx in ipairs({{environment='ROUTE',kind='wild',terrain='grass'},
 {environment='CAVE',kind='wild',terrain='water'},
 {environment='CAVE',kind='wild',battleType='fish'}, {}}) do assert(not Cave.matches(ctx)) end
math.randomseed(45);local nextRandom=math.random();math.randomseed(45)
local vertices=Cave.vertices()
assert(math.random()==nextRandom,'cave consumes gameplay RNG')
assert(#vertices/3<65000 and #vertices%3==0)
for _,v in ipairs(vertices) do
 assert(#v==10)
 for _,n in ipairs(v) do assert(n==n and math.abs(n)<1000) end
end
local env={daytime='DAY',modelTint={1,1,1}}
assert(Cave.lighting(env).modelTint~=env.modelTint and env.modelTint[1]==1)
local A=require(root..'battle_torch_shadows');local B=A.new()
A.night=false;B.night=true;assert(not A.night,'cave changed forest lighting state')
Cave.release();B.release()
print('Cave routing, geometry, RNG isolation and independent lighting passed: '..#vertices/3)
