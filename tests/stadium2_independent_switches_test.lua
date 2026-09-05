local f=assert(io.open("lib/gen1_battle.lua","rb")); local s=f:read("*a"); f:close()
local models,battles=true,true
local loads,releases=0,0
local Scene={new=function() return {sync=function() end} end}
local Gen1={finish=function() end}
local env=setmetatable({Scene=Scene,Gen1=Gen1,installed=true,configured=151,
 Importer={modelsEnabled=function() return models end,battleEnabled=function() return battles end,
 available=function() return true end},dexOf=function() return 25 end},{__index=_G})
local function section(a,b)
 local i=assert(s:find(a,1,true)); local j=assert(s:find(b,i+#a,true))
 local fn=assert(loadstring(s:sub(i,j-1)));setfenv(fn,env);fn()
end
section("function Gen1.ensure", "function Gen1.update")
section("function Gen1.enabled", "function Gen1.ready")
section("function Scene:sync()", "local function safeCall")
local function actor() return {load=function() loads=loads+1 end,
 release=function() releases=releases+1 end} end
local scene=setmetatable({battle={data={}},actors={player=actor(),enemy=actor()},
 substituteActors={player=actor(),enemy=actor()},shownMon=function() return {} end},{__index=Scene})
for _,choice in ipairs({{true,true},{false,true},{true,false},{false,false},{true,true}}) do
 models,battles=choice[1],choice[2]
 assert(Gen1.enabled()==battles)
 assert(Gen1.ensure({})==battles)
 local before=loads
 scene:sync()
 assert(loads==before+(models and 2 or 0))
 if not models then assert(releases>0) end
end
print("independent Stadium battle/model switches: passed")
