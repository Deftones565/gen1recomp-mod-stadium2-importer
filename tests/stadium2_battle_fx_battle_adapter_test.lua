package.path="./?.lua;./?/init.lua;"..package.path

local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Scene=require("mods.STADIUM2_IMPORTER.lib.battle_scene")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end
local function near(got,want,message)
  ok(math.abs(got-want)<1e-9,message)
end

-- The ordinary presentation must not construct an FX player while the beta
-- option is disabled.
local disabledFactoryCalls=0
local disabled=Adapter.new({
  betaBattleFxEnabled=function() return false end,
  newBattleFxPlayer=function() disabledFactoryCalls=disabledFactoryCalls+1 end,
})
ok(disabled==nil and disabledFactoryCalls==0,"beta-off adapter is zero-cost")

local captured
local fakePlayer={
  triggers=0,updates=0,draws=0,releases=0,
  trigger=function(self,context) self.triggers=self.triggers+1;captured=context;return {id=4} end,
  update=function(self,dt) self.updates=self.updates+1;self.dt=dt;return true end,
  draw=function(self,context) self.draws=self.draws+1;self.drawContext=context;return {drawn=1} end,
  release=function(self) self.releases=self.releases+1;return true end,
}
local factoryCalls=0
local warnings={}
local adapter=assert(Adapter.new({
  betaBattleFxEnabled=function() return true end,
  newBattleFxPlayer=function(options)
    factoryCalls=factoryCalls+1
    captured=options
    return fakePlayer
  end,
},{warn=function(message) warnings[#warnings+1]=message end}))
ok(factoryCalls==1,"beta-on adapter constructs one player")
ok(type(captured.contextForParticle)=="function" and type(captured.resolvePlacement)=="function",
  "adapter injects placement resolvers")

local sceneHost={
  arena=true,
  arenaScale=.05,
  modelMatrix=function()
    return {.05,0,0,0,0,.05,0,0,0,0,.05,0,0,0,0,1}
  end,
}
local sceneContext={
  scene={host=sceneHost,arena=true},
  world={actorSlots={player={x=-7.5,y=0,z=0},enemy={x=7.5,y=0,z=0}}},
}
local particle={event={context={sourceSide="enemy"}},position={1,2,3}}
local placement=captured.contextForParticle(particle,sceneContext)
ok(placement.sourceSide=="enemy" and placement.worldUnits==.05,
  "placement context preserves source side and Stadium scale")
local resolved=assert(captured.resolvePlacement({flags=0x480},placement))
ok(resolved.resolved,"lane placement resolves")
near(resolved.position[1],7.55,"lane placement converts source X once")
near(resolved.position[2],.1,"lane placement converts source Y once")
near(resolved.position[3],.15,"lane placement converts source Z once")
ok(resolved.scale==.05,"fixed initial scale converts at renderer boundary")

local effect=assert(adapter:trigger(7,"enemy",true))
ok(fakePlayer.triggers==1 and captured.targetSide=="player"
  and captured.sourceSide=="enemy" and captured.alternate==true,
  "trigger maps source and opposite target sides")
ok(adapter:update(1/30) and fakePlayer.updates==1 and fakePlayer.dt==1/30,
  "update delegates the persistent FX clock")
local drawResult=assert(adapter:draw(sceneContext))
ok(drawResult.drawn==1 and fakePlayer.draws==1,"draw delegates at the shared seam")
ok(adapter:release() and adapter:release()==false and fakePlayer.releases==1,
  "release is idempotent and releases player exactly once")

-- The common scene owns the injected bridge and releases it once, while its
-- update seam remains harmless for scenes that do not opt into FX.
local seam={updates=0,releases=0,update=function(self,dt)self.updates=self.updates+1;return dt end,
  release=function(self)self.releases=self.releases+1;return true end}
local common=Scene.new({battleFx=seam})
ok(common:updateBattleFx(.25)==.25 and seam.updates==1,"shared update seam delegates")
common:release();common:release()
ok(seam.releases==1,"shared scene releases bridge once")
local ordinary=Scene.new({})
ok(ordinary:updateBattleFx(.25)==nil,"shared scene beta-off update is a no-op")
ordinary:release()

-- Keep the render ordering contract visible in a ROM-free focused check.
local source=assert(io.open("mods/STADIUM2_IMPORTER/lib/battle_scene.lua","rb")):read("*a")
local geometry=assert(source:find("Extensions%.geometry%(ext%)",1))
local fx=assert(source:find("self%.battleFx%.draw",geometry+1))
local restore=assert(source:find("restoreWorldTarget%(self,g%)",fx+1))
ok(geometry<fx and fx<restore,"FX draw follows geometry and restores world target")

print(("%d checks passed (Stadium 2 battle-FX adapter/seam)"):format(checks))
