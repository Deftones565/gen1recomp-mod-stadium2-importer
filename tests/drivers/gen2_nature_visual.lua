-- Kenney Nature live battle smoke test; uses the arena test output directory.
local U=require("tests.drivers.util")
local Mon=require("src.battle.gen2.Mon")

local CASES={
  wild={map="ROUTE_29",x=44,y=12,reason="wild:classic",classic=true,
    file="01-wild-classic.png"},
  fishing={map="ROUTE_29",x=44,y=12,reason="wild:classic",classic=true,
    battleType="fish",file="02-fishing-classic.png"},
  outdoor_trainer={map="ROUTE_29",x=44,y=12,trainer="YOUNGSTER",
    arena=28,reason="outdoor",file="03-outdoor-trainer-park.png"},
  indoor_trainer={map="EARLS_POKEMON_ACADEMY",x=3,y=4,trainer="YOUNGSTER",
    arena=27,reason="indoor",file="04-indoor-trainer-classroom.png"},
  gym={map="VIOLET_GYM",x=5,y=7,trainer="FALKNER",
    arena=0,reason="map:VIOLET_GYM",file="05-violet-gym.png"},
}

local function waitFor(game,predicate,frames,message)
  for _=1,frames do
    local value=predicate()
    if value then return value end
    U.wait(1)
  end
  error(message,0)
end

local function saveSceneCanvas(canvas,path)
  assert(canvas and canvas.newImageData,"Stadium battleStatus().shot is unavailable")
  local image=canvas:newImageData()
  local encoded=image:encode("png")
  local bytes=encoded and encoded.getString and encoded:getString()
  assert(type(bytes)=="string" and #bytes>0,"could not encode Stadium scene canvas")
  local handle=assert(io.open(path,"wb"))
  handle:write(bytes)
  handle:close()
  return true
end

return function(game)
  local name="outdoor_trainer"
  local case=assert(CASES[name],"unknown Stadium arena visual case: "..name)
  local out=os.getenv("STADIUM2_ARENA_VISUAL_DIR") or "/tmp/stadium2-context-arenas"

  U.wait(45)
  local world=assert(game.world,"Gen 2 world did not boot")
  local loader=assert(game.mods,"mod loader is unavailable")
  local exports=assert(loader.exports and loader.exports.STADIUM2_IMPORTER,
    "STADIUM2_IMPORTER is not enabled for this Gen 2 run")

  -- The loader's live option table is the backing store used by mod.options.
  -- This test changes only the running test process; it does not persist the
  -- choice or rewrite the user's options file.
  loader.modOptions.STADIUM2_IMPORTER=loader.modOptions.STADIUM2_IMPORTER or {}
  local options=loader.modOptions.STADIUM2_IMPORTER
  options.stadium2_environment="kenney"
  options.stadium2_models=true
  options.stadium2_battle=true
  options.stadium2_beta_arena_test=true
  options.stadium2_beta_arena_tod=false

  waitFor(game,function()
    local status=exports.status and exports.status()
    return status and status.state=="ready"
  end,1800,"Stadium 2 model cache did not become ready")

  assert(world:setMap(case.map,case.x,case.y,"down"),
    "could not enter "..case.map)
  U.wait(8) -- map.entered must reach the contextual resolver before battle.started

  local player=assert(Mon.new(game.data,"CROCONAW",20),"could not build CROCONAW")
  local enemy=assert(Mon.new(game.data,"KOFFING",15),"could not build KOFFING")
  game.save.party={player}
  local battleOptions={battleType=case.battleType}
  if case.trainer then
    battleOptions.trainer={class=case.trainer,classId=case.trainer,
      name=case.trainer,party={enemy}}
  else
    battleOptions.wild=enemy
  end
  assert(world:startBattle(battleOptions),
    "could not start the visual encounter")

  local screen=waitFor(game,function()
    local top=game.stack:top()
    return top and top.battle and top or nil
  end,900,"Gen 2 battle screen did not appear")
  assert(screen.battle,"battle screen has no live battle")

  local status=waitFor(game,function()
    local value=exports.battleStatus and exports.battleStatus()
    return value and value.active and value or nil
  end,600,"Stadium 2 Importer did not own the encounter")
  assert(status.betaArena==false,"Kenney clearing must take precedence over beta park")
  local Nature=require("mods.STADIUM2_IMPORTER.lib.battle_nature")
  waitFor(game,function() return Nature.triangles end,300,"Kenney mesh was not drawn")
  -- Let entrance animation, arena FX and the camera settle before the proof
  -- frame. The assertion above has already tied this image to the resolver.
  U.wait(150)
  local path=out.."/kenney-grass.png"
  local fullPath=path:gsub("%.png$","-full-window.png")
  assert(U.shot(game,fullPath),"failed to capture "..fullPath)
  status=assert(exports.battleStatus(),"battle status disappeared before scene capture")
  assert(saveSceneCanvas(status.shot,path),"failed to capture "..path)
  print(("[stadium2-arena-visual] PASS case=%s map=%s arena=%s reason=%s scene=%s full=%s")
    :format(name,case.map,tostring(status.arenaIndex),tostring(status.arenaReason),path,fullPath))
  love.event.quit()
end
