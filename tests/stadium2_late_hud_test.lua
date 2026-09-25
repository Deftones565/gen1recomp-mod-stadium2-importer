package.path="./?.lua;./?/init.lua;"..package.path
local Host={}
Host.__index=Host
for _,name in ipairs({"draw","drawPicsLayer","drawHUDs","drawTextArea","drawAnimLayer"}) do
  Host[name]=function() end
end
Host.isWideBattleLayout=function() return true end
package.loaded["src.battle.BattleState"]=Host
local Gen1=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
Importer.battleEnabled=function() return true end
Importer.available=function() return true end
local Ownership=require("mods.STADIUM2_IMPORTER.lib.battle_ui_ownership")
local hooks={}
local mod={find=function(id) if id=="quality_of_life" then return {} end end,
  hooks={wrap=function(_,name,fn) hooks[name]=fn end}}
Ownership.bind(mod,function(state) return Gen1.currentScene() and Gen1.currentScene().battle==state end)
function Host:statusHUDVisible()
  return hooks["battle.status_hud_visible"](function() return not self.foreign end,self)
end
local target="native"
local stack,draws={},{}
local g={}
function g.newCanvas() return {setFilter=function() end,release=function() end} end
function g.push() stack[#stack+1]=target end
function g.pop() target=table.remove(stack) end
function g.setCanvas(value) target=value end
function g.newQuad(x,y,w,h) return {x=x,y=y,w=w,h=h} end
function g.draw(_,q) draws[#draws+1]={target=target,quad=q} end
for _,name in ipairs({"origin","setScissor","setShader","clear","setColor","setBlendMode","scale"}) do
  g[name]=function() end
end
love={graphics=g}
local world={getDimensions=function() return 640,576 end}
local scene
Gen1.Scene.new=function(battle)
  scene={battle=battle,readyFrame=true,width=640,height=576,
    hudBox={lx=0,ly=0,scale=4},sync=function() end,update=function() end,
    release=function() end,
    composeWorld=function(self)
      self.statusHudOwned=Ownership.claimStatus(battle)
      return world
    end}
  return scene
end
Gen1.bind(mod)
assert(Gen1.install())
local battle=setmetatable({game={save={options={}}}},Host)
local drawsLate=0
local explode=false
local function late(self)
  Host.draw(self)
  drawsLate=drawsLate+1
  assert(target==scene.statusOverlay,"late enhancement did not enter capture")
  if explode then error("deliberate overlay failure") end
end
battle.draw=late
assert(Gen1.ensure(battle))
Gen1.update(0)
battle:draw()
assert(drawsLate==1 and target=="native" and #stack==0)
assert(not battle:statusHUDVisible(),"capture flag leaked")
local onWorld=0
for _,d in ipairs(draws) do if d.target==world then onWorld=onWorld+1 end end
assert(onWorld==2,"late HUD did not follow both detached cards")
draws={};battle.foreign=true
battle:draw()
for _,d in ipairs(draws) do assert(d.target~=world,"late HUD leaked over foreign UI") end
explode=true
assert(not pcall(battle.draw,battle))
assert(target=="native" and #stack==0,"failed overlay leaked graphics state")
assert(not battle:statusHUDVisible(),"failed overlay reopened native HUD")
Gen1.finish(battle)
assert(battle.draw==late,"teardown did not restore original instance wrapper")
print("Late HUD: once-only draw, detached placement, foreign ownership, failure cleanup and teardown passed")
