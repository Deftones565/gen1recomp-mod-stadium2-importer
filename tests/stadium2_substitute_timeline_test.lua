package.path="./?.lua;./?/init.lua;"..package.path
local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
local pic
local mons={player={hp=100},enemy={hp=100}}
local vol={player={},enemy={}}
local battle={player=mons.player,enemy=mons.enemy,
  volatile=function(_,mon) return mon==mons.player and vol.player or vol.enemy end}
local screen={battle=battle,game={data={moves={FLY={index=19,effect="EFFECT_FLY"}}}},
  animPicState=function() return pic end}
local hits=0
local scene=setmetatable({battle=battle,screen=screen,readyFrame=true,
  actors={player={mon=mons.player,renderer={}},enemy={mon=mons.enemy,renderer={}}},
  substituteActive={player=false,enemy=false},recordedSubstitute={player=0,enemy=0},
  eventVisuals=setmetatable({},{__mode="k"}),vanish={player={},enemy={}},
  sync=function() end,
  ensureSubstitute=function() return {hit=function() hits=hits+1 end} end},Gen2.Scene)
local function event()
  local e={kind="message",text="任意の翻訳"}
  scene:recordEvent(e)
  return e
end
local before=event()
vol.player.substitute=25
local made=event()
vol.player.substitute=15
local struck=event()
vol.player.substitute=nil
local breaking=event()
local broken=event()
scene:handleEvent(before)
assert(scene:visualState("player")=="pokemon","future resolution leaked into presentation")
scene:handleEvent(made)
assert(scene:visualState("player")=="substitute","successful creation did not show doll")
pic={pic=false};screen.anim={}
assert(scene:visualState("player")=="pokemon","dropsub did not expose the attacking Pokemon")
pic={pic="substitute"}
assert(scene:visualState("player")=="substitute","raisesub did not restore the doll")
pic={pic="substitute",hidden=true}
assert(scene:visualState("player")=="hidden","doll ignored native hidden state")
pic=nil;screen.anim=nil
scene:handleEvent(struck)
assert(hits==1 and scene:visualState("player")=="substitute")
scene:handleEvent(breaking)
assert(hits==2 and scene:visualState("player")=="substitute","breaking impact lost its doll")
scene:handleEvent(broken)
assert(scene:visualState("player")=="pokemon","localized break did not restore Pokemon")
scene:handleEvent({kind="move",side="player",move="SUBSTITUTE",missed=true})
assert(scene:visualState("player")=="pokemon","failed Substitute created a doll")
pic={pic="minimize"};screen.anim={}
assert(scene:picScale("player")==.35,"Minimize ignored native visual command")
pic={};scene:handleEvent({kind="move",side="player",move="FLY",animParam=1})
assert(scene:visualState("player")=="pokemon","Fly vanished before its native departure")
pic={hidden=true}
assert(scene:visualState("player")=="hidden")
scene:handleEvent({kind="move",side="player",move="FLY",wasVanished=true})
assert(scene:visualState("player")=="hidden")
pic={hidden=false}
assert(scene:visualState("player")=="pokemon","Fly return did not restore model")
print("Substitute timeline: queued creation, drop/raise, impacts, localized break, failure, Minimize and Fly passed")
