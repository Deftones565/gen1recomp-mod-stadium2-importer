package.path="./?.lua;./?/init.lua;"..package.path
local Gen1=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
local Actor=require("mods.STADIUM2_IMPORTER.lib.battle_actor")
local mon={species=50,hp=20}
local b={mon=mon,charging={id="FLY"}}
local pf={kind="squish",t=12}
local rig={worldMetrics=function() return {height=20,floor=0,radius=5} end}
local actor={renderer=rig,dex=50,scale=function() return 1 end}
local scene=setmetatable({battle={player=b,picFx={[b]=pf},growInScale=function() end},
  actors={player=actor}},Gen1.Scene)
assert(scene:picElevation("player")==1.5,"Fly must ascend during its charge script")
local flying=scene:modelMatrix("player",actor)
pf.kind=nil
local standing=scene:modelMatrix("player",actor)
assert(flying[8]>standing[8],"Fly elevation never reached the world matrix")
pf.minimized=true
local small=scene:modelMatrix("player",actor)
assert(math.abs(small[1]/standing[1]-.35)<.001,"Minimize did not scale actual geometry")
pf.minimized=nil;pf.kind="slideDown";pf.t=10.5;b.charging={id="DIG"}
assert(scene:picElevation("player")==-.5,"Dig must sink monotonically")
pf.kind="slideUp";pf.t=7
assert(scene:picElevation("player")==-.5,"Dig must emerge from below ground")
pf.kind=nil;pf.hidden=true
assert(scene:hostHidden("player"),"underground model ignored persistent host hide")
pf.hidden=nil
assert(not scene:hostHidden("player"),"return did not clear the hidden state")
local a=Actor.new("player");a.dex=50
a.renderer={setMove=function() return true end,
  setContext=function() return true end}
assert(a:attack(91),"Diglett Dig did not start the source move")
local pic={pic="minimize"}
local g2=setmetatable({actors={player={mon=mon}},substituteActive={},
  screen={anim={},animPicState=function() return pic end}},Gen2.Scene)
assert(g2:picScale("player")==.35)
pic=nil;g2.screen.anim=nil
assert(g2:picScale("player")==.35,"Gen 2 Minimize ended with the native script")
g2.actors.player.mon={}
assert(g2:picScale("player")==1,"Minimize leaked across a switch")
print("Model motion: world-space Fly/Dig, geometry Minimize, hidden states and travel reset passed")
