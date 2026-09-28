package.path="./?.lua;./?/init.lua;"..package.path
-- In-battle evolution (user-requested extension, not Stadium 2 behaviour):
-- reading the host's Gen 1 / Gen 2 evolution from the stack, the old/new
-- model swap on the host's beats, the Pokemon sent out when it is not the
-- one out, hiding the host screens, and standing aside when a model or the
-- Stadium box is missing. No LOVE, no ROM (stubbed actors and renderer).
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

-- stubs ---------------------------------------------------------------
local loads={}
local FakeActor={}
FakeActor.__index=FakeActor
function FakeActor.new(side,opts) return setmetatable({side=side,opts=opts,played={}},FakeActor) end
function FakeActor:load(_,mon,dex)
  loads[#loads+1]=dex
  if dex==999 then return false end
  self.mon,self.dex,self.renderer=mon,dex,{worldMetrics=function() return {floor=0,height=10,radius=5} end}
  return true
end
function FakeActor:release() self.renderer=nil;self.released=true end
function FakeActor:play(ctx) self.played[#self.played+1]=ctx end
function FakeActor:update() end
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_actor"]=FakeActor
package.loaded["mods.STADIUM2_IMPORTER.lib.renderer"]={
  lookAt=function(...) return {"view",...} end,matMul=function(a,b) return {"vp",a,b} end}
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_camera"]={project=function() return 0,0,true end}
local uiAvailable=true
local drawn
package.loaded["mods.STADIUM2_IMPORTER.ui.lib.stadium_ui"]={available=function() return uiAvailable end,
  toLatin1=function(s) return s end,tryDrawMessage=function(_,lines) drawn=lines return true end}
package.loaded["mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence"]={SEND_OUT_ENTRY=0x122}

local ES,TB,EA={}, {}, {}
package.loaded["src.ui.EvolutionState"]=ES
package.loaded["src.render.TextBox"]=TB
package.loaded["src.ui.gen2.EvolutionAnim"]=EA
package.loaded["src.core.RomText"]=function(_,_,default,name) return (default:format(name)) end

local Evolution=require("mods.STADIUM2_IMPORTER.lib.battle_evolution")

-- Gen 1's flash schedule (the host's evoShowsNew) --------------------------
ok(Evolution.gen1ShowsNew(0)==false and Evolution.gen1ShowsNew(16)==true,"round 1: hold the old pic 16, then swap")
ok(Evolution.gen1ShowsNew(19)==false,"and back after 3 frames")
ok(Evolution.gen1ShowsNew(10000)==true,"the new pic after the eighth round")

-- Gen 1 --------------------------------------------------------------------
local data={pokemon={CHARMANDER={name="CHARMANDER",dex=4},CHARMELEON={name="CHARMELEON",dex=5},
  PIKACHU={name="PIKACHU",dex=25}}}
local evolving={species="CHARMANDER",level=16}
local out={species="PIKACHU",level=20}
local game={data=data,save={party={out,evolving}},stack={states={}}}
local battle={game=game,data=data,evolutionsChecked=true,leveledUp={[evolving]=true}}
local signals={}
local scene={battle=battle,game=game,readyFrame=true,
  actors={player={warn=nil,label="Gen 1 battle"}},
  shownMon=function(_,side) return side=="player" and out or nil end,
  battleFx={signalEffect=function(_,entry,side) signals[#signals+1]={entry,side} end},
  modelMatrix=function() return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1} end}

local intro=setmetatable({pages={{"What?","CHARMANDER is"},{"evolving!"}},
  visibleText=function() return {"What?","CHARMANDER is"} end},TB)
game.stack.states={battle,intro}
local info=Evolution.gen1Info(scene)
ok(info and info.mon==evolving and info.phase=="announce","the intro box names the evolving Pokemon")
local other=setmetatable({pages={{"PIKACHU learned","THUNDER!"}},visibleText=function() return {} end},TB)
game.stack.states={battle,other}
ok(Evolution.gen1Info(scene)==nil,"any other box over the battle is not an evolution")

game.stack.states={battle,intro}
Evolution.step(scene,1/60)
local e=scene.evolution
ok(e and e.oldActor and e.oldActor.dex==4,"old form loaded")
ok(e.oldActor.played[1]=="entrance" and signals[1] and signals[1][1]==0x122 and signals[1][2]=="player",
  "not the one out: sent out with Stadium's send-out effect")
ok(Evolution.hides(scene,intro),"the intro box is hidden while presenting")
local handled,actor=Evolution.actorFor(scene,"enemy")
ok(handled and actor==nil,"the opponent's slot stays empty")
handled,actor=Evolution.actorFor(scene,"player")
ok(handled and actor==e.oldActor,"the old form stands in the player's slot")
ok(Evolution.drawHud(scene,{width=1920,height=1080}) and drawn[1]=="What?","the host text in the Stadium box")

local movie=setmetatable({mon=evolving,newSpecies="CHARMELEON",t=10},ES)
game.stack.states={battle,intro,movie}
Evolution.step(scene,1/60)
ok(scene.evolution==e and e.newActor and e.newActor.dex==5,"the movie names the new species: new form loaded")
ok(Evolution.hides(scene,movie) and Evolution.hides(scene,intro),"the host movie and its box are hidden")
movie.t=80+16
Evolution.step(scene,.5)
ok(e.phase=="flash" and e.showNew==true and e.white>0,"flash: white, forms swap on the host's beats")
movie.t=80+19
Evolution.step(scene,.5)
ok(e.showNew==false and #e.particles>0,"back to the old form; sparkles rise")
ok(select(2,Evolution.actorFor(scene,"player"))==e.oldActor and e.oldActor.evolveWhite>0,"the drawn form is white")
movie.done=true
evolving.species="CHARMELEON"
Evolution.step(scene,.1)
ok(e.phase=="evolved" and e.showNew and e.revealed,"evolved: the new form, with a burst")
for _=1,40 do Evolution.step(scene,.1) end
ok(e.white==0,"the white leaves the new form")
local frame={eye={0,10,20},focus={0,0,0},projection={},view={},letterbox={}}
local closed=e:frame(frame)
ok(closed~=frame and closed.focus[2]>0,"the camera closes in on the Pokemon")
local oldForm,newForm=e.oldActor,e.newActor
game.stack.states={battle}
for _=1,40 do Evolution.step(scene,.1) end
ok(scene.evolution==nil and oldForm.released and newForm.released,"afterwards the camera returns and the models go")
ok(Evolution.hides(scene,movie)==false,"nothing hidden afterwards")

-- a missing model: the host's own evolution screen stays
local evolving2={species="CHARMANDER",level=16}
battle.leveledUp={[evolving2]=true}; game.save.party={evolving2}
data.pokemon.MISSINGNO={name="MISSINGNO",dex=999}
local movie2=setmetatable({mon=evolving2,newSpecies="MISSINGNO",t=90},ES)
game.stack.states={battle,movie2}
Evolution.step(scene,.1)
ok(scene.evolution==nil and not Evolution.hides(scene,movie2),"new model unavailable: the host screen stays")
Evolution.step(scene,.1)
ok(scene.evolution==nil,"and it is not retried every frame")

-- no Stadium box: the host screen stays
uiAvailable=false
local evolving3={species="CHARMANDER",level=16}
local movie3=setmetatable({mon=evolving3,newSpecies="CHARMELEON",t=10},ES)
game.stack.states={battle,movie3}
Evolution.step(scene,.1)
ok(scene.evolution and not Evolution.hides(scene,movie3),"no Stadium UI art: nothing hidden")
ok(Evolution.actorFor(scene,"player")==false,"and the scene keeps its own battlers")
uiAvailable=true
game.stack.states={battle}
for _=1,40 do Evolution.step(scene,.1) end

-- Gen 2 --------------------------------------------------------------------
local g2mon={species=155,level=14}
local screen={}
local game2={data={pokemon={}},stack={states={}}}
screen.game=game2
local scene2={screen=screen,game=game2,readyFrame=true,actors={player={}},
  shownMon=function() return g2mon end,
  modelMatrix=function() return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1} end}
local anim=setmetatable({mon=g2mon,oldSpecies=155,newSpecies=156,phase="evolving",
  lines={"What? CYNDAQUIL","is evolving!"},rounds={1,2,3,4,5,6,7,8},round=1},EA)
game2.stack.states={screen,anim}
Evolution.step(scene2,1/60)
local e2=scene2.evolution
ok(e2 and e2.oldActor.dex==155 and e2.newActor.dex==156,"Gen 2: both forms from the EvolutionAnim")
ok(#e2.oldActor.played==0,"the one out: no send-out")
ok(Evolution.isOut({shownMon=function() return {species=155} end,battle={player=g2mon}},g2mon),
  "Gen 2: a display copy on screen still counts the battle's active Pokemon as out")
ok(Evolution.hides(scene2,anim),"the whole host evolution screen is hidden")
anim.phase="flash"; anim.showNew=true; anim.round=5
Evolution.step(scene2,.2)
ok(e2.phase=="flash" and e2.showNew and e2.progress==.5,"Gen 2 flash follows showNew and the rounds")
anim.phase="stopped"; anim.canceled=true; anim.lines={"Huh? CYNDAQUIL","stopped evolving!"}
Evolution.step(scene2,.2)
ok(e2.phase=="canceled" and not e2.showNew,"cancelled: back to the old form")
Evolution.drawHud(scene2,{width=800,height=600})
ok(drawn[2]=="stopped evolving!","Gen 2's lines in the Stadium box")
anim.phase="congrats"; anim.canceled=false
Evolution.step(scene2,.2)
ok(e2.phase=="evolved","congrats: evolved")

-- The camera: in front of the Pokemon (towards its opponent), and steady
-- while forms of different heights trade places on the flash beats.
do
  local tall={[155]=10,[156]=18}
  local scene3={screen=screen,game=game2,readyFrame=true,actors={player={}},
    shownMon=function() return g2mon end,
    actorPosition=function(_,side) return side=="player" and {0,0,24} or {0,0,-24} end,
    modelMatrix=function(_,_,actor) return {1,0,0,0, 0,1,0,0, 0,0,1,24, 0,0,0,1} end}
  local anim3=setmetatable({mon=g2mon,oldSpecies=155,newSpecies=156,phase="flash",showNew=false,
    lines={},rounds={1,2,3,4,5,6,7,8},round=1},EA)
  game2.stack.states={screen,anim3}
  Evolution.step(scene3,.1)
  local e3=scene3.evolution
  for _,a in ipairs({e3.oldActor,e3.newActor}) do
    local h=tall[a.dex]
    a.renderer={worldMetrics=function() return {floor=0,height=h,radius=5} end}
  end
  for _=1,60 do Evolution.step(scene3,.1) end
  local c1,s1=e3:bounds()
  anim3.showNew=true; Evolution.step(scene3,1/60)
  local c2,s2=e3:bounds()
  ok(math.abs(c1[2]-c2[2])<1e-3 and math.abs(s1-s2)<1e-3 and math.abs(s1-18)<1e-3,
    "the framing holds both forms: no jump when they swap")
  local fr=e3:frame({eye={0,20,70},focus={0,0,0},projection={},view={},letterbox={}})
  ok(fr.eye[3]<24 and math.abs(fr.focus[2]-9)<1e-6,"the camera stands in front of the Pokemon (on its opponent's side)")
  game2.stack.states={screen}
  for _=1,40 do Evolution.step(scene3,.1) end
end

-- install: the battle's own text box and HUD stay off while presenting
local hooks={}
local mod={hooks={wrap=function(_,name,fn) hooks[name]=fn end},exports={}}
local current=scene2
Evolution.install(mod,function() return current end)
anim.phase="evolving"; game2.stack.states={screen,anim}
Evolution.step(scene2,.1)
local nextCalled
local function nextVisible() nextCalled=true return true end
ok(hooks["battle.bottom_ui_visible"](nextVisible,screen)==false,"the battle's text box hidden while presenting")
ok(hooks["battle.status_hud_visible"](nextVisible,screen)==false,"and its status boxes")
ok(hooks["battle.bottom_ui_visible"](nextVisible,{})==true and nextCalled,"other screens untouched")
ok(mod.exports.evolutionPresented()==true,"presented, for other UI mods")

print(checks.." checks passed (in-battle evolution)")
