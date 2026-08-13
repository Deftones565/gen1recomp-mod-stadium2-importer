package.path="./?.lua;./?/init.lua;"..package.path

local unownOk=pcall(require,"src.core.gen2.Unown")
if not unownOk then
  package.preload["src.core.gen2.Unown"]=function()
    return {
      index=function(value) return type(value)=="number" and value or nil end,
      letterFromDVs=function() return 1 end,
      name=function(index) return string.char(64+(tonumber(index) or 1)) end,
    }
  end
end

local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local calls={}
local handlerRuntime
local rig={finished=false,frame=0,animIndex=1,
  setContext=function(self,name,loop) calls[#calls+1]=name;return name~="missing" end,
  setMove=function() return true end,
  setHandlerRuntime=function(_,runtime) handlerRuntime=runtime end,
  step=function() end,
}
local actor=Gen2.Actor.new("player")
actor.renderer=rig
actor:entrance()
ok(actor:scale()==0,"send-out model begins at zero scale")
actor.grow.time=actor.grow.duration*.5
ok(math.abs(actor:scale()-.5)<.0001,"send-out uses a symmetric smoothstep")
ok(not actor:play("idle",true),"idle cannot interrupt entrance")
ok(actor:attack(1) and actor.context=="attack","attack can supersede entrance")
actor.pendingFaint=true
ok(not actor:attack(1),"pending faint cannot be overwritten by an attack")
actor:faint()
ok(actor.context=="faint" and not actor:play("attack",false),"faint is final")
rig.finished=true
rig.frame=12
rig.animIndex=3
actor.dex=109
actor.dynamicObjectIndex=1
actor:update(1/30)
ok(actor.faintFinished and actor.context=="faint","faint holds its terminal pose")
ok(handlerRuntime and handlerRuntime.species==109 and handlerRuntime.dynamicObjectIndex==1
  and handlerRuntime.animationState==3
  and handlerRuntime.animationFrame==12 and handlerRuntime.dynamicObjectEnabled==true
  and handlerRuntime.dynamicObjectUpdateEnabled==true,
  "battle actor supplies the fragment-26 dynamic-object runtime")

local scene=Gen2.Scene.new({})
scene.actors.player=actor
scene.screen={picHidden={player=false},animPicState=function() return nil end}
actor.mon={hp=0}
ok(scene:covered("player"),"finished faint continues suppressing the native 2D pic")
ok(not scene:modelVisible("player"),"finished faint leaves an empty 3D platform")

local owner={}
local live={battle=owner,screen={phase="resolving"}}
ok(Gen2._shouldDeferFinish(live,owner),
  "battle.ended cannot tear down Gold's visible result queue")
live.screen.phase="done"
ok(not Gen2._shouldDeferFinish(live,owner),
  "scene may release after BattleState actually finishes")

local model={auxAnims={},anims={},textures={}}
local prim={tex=1,fxFrames={4,5,6}}
ok(Pack.textureIndex(model,prim,nil,0,nil,0)==4,"model FX starts on first frame")
ok(Pack.textureIndex(model,prim,nil,0,nil,4)==5,"model FX follows the 30 Hz callback clock")

local special={}
local oldSpecial,oldRenderer=Importer.newSpecialRenderer,Importer.newRenderer
local function formRig()
  return {finished=false,frame=0,setContext=function() return true end,
    setMove=function() return true end,setHandlerRuntime=function() end,
    step=function() end,release=function() end}
end
Importer.newSpecialRenderer=function(name)
  special[#special+1]=name
  return formRig()
end
Importer.newRenderer=function() return formRig() end
local formActor=Gen2.Actor.new("enemy")
local data={pokemon={UNOWN={dex=201}}}
ok(formActor:load(data,{species="UNOWN",unownLetter=2,hp=20})
  and special[#special]=="unown_b","Unown B selects its dumped Stadium 2 form")
ok(formActor:load(data,{species="UNOWN",unownLetter=26,hp=20,shiny=true})
  and special[#special]=="unown_z_shiny",
  "shiny Unown Z selects the shiny form-specific pack")
Importer.newSpecialRenderer,Importer.newRenderer=oldSpecial,oldRenderer

print(("%d checks passed (Stadium 2 Gen 2 actor parity)"):format(checks))
