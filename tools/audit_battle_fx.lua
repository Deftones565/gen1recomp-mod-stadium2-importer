-- Run from the repository root. CPU audit: real ROM models/resources, no GPU.
-- STADIUM2_AUDIT_TICKS defaults to 360; draw sampling defaults to every 15 ticks.
package.path="./?.lua;./?/init.lua;"..package.path
local prefix="mods.STADIUM2_IMPORTER.lib."
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Native=require(prefix.."stadium2_battle_fx_native")
local Motion=require(prefix.."stadium2_battle_fx_motion")
local Preview=require("mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx")
local Rom=require(prefix.."rom")
local Layout=require(prefix.."layout")
local Extract=require(prefix.."extract")
local Fragment=require(prefix.."fragment")
local Renderer=require(prefix.."renderer")
local Dispatch=require(prefix.."animation_dispatch")
local path=os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file=assert(io.open(path,"rb"));local rom=file:read("*a");file:close()
local catalog=assert(FxRom.catalog(rom))
local names=assert(Dispatch.moveNames(rom))
local ticks=tonumber(os.getenv("STADIUM2_AUDIT_TICKS")) or 360
local stride=tonumber(os.getenv("STADIUM2_AUDIT_DRAW_STRIDE")) or 15
local selectedMove=tonumber(os.getenv("STADIUM2_AUDIT_MOVE"))
local staticOnly=os.getenv("STADIUM2_AUDIT_STATIC_ONLY")=="1"
assert(ticks>=1 and ticks%1==0 and stride>=1 and stride%1==0)
assert(not selectedMove or selectedMove>=1 and selectedMove<=251 and selectedMove%1==0)
local archive=assert(Rom.archiveAt(rom,Layout.MODEL_TABLE_START))
local function actor(species)
  local data=assert(Rom.decompress(assert(Rom.recordBytes(rom,archive.records[species+1]))))
  local info=assert(Extract.fragmentInfo(data))
  data=Extract.runtimeFragmentForSpecies(rom,species,data)
  Fragment.setBase(info.sourceBase)
  local model=assert(Fragment.extract(data,"audit-species-"..species))
  local rows=assert(Dispatch.forSpecies(rom,species));local raw={}
  for i=0,rows.n-1 do raw[#raw+1]=rows[i].raw end
  model.species=species;model.fxDispatch=table.concat(raw)
  model.fxBattleProfile=Dispatch.battleProfileBytes(rom,species)
  model.fxContextScales=Dispatch.contextScaleBytes(rom,species)
  -- Only the skeleton/markers are needed; model geometry is not GPU-tested.
  model.prims={};model.textures={}
  if type(model.rootScale)=="table" then
    model.rootScaleVector=model.rootScale;model.rootScale=model.rootScale[1]
  end
  return {renderer=assert(Renderer.new(model,{flipY=false})),context="idle"}
end
local actors={player=actor(159),enemy=actor(109)}
local slots={player={-7.5,0,0},enemy={7.5,0,0}}
local host={visualActor=function(_,side)return actors[side]end,
  modelMatrix=function(_,side)
    local s=side=="player" and .05 or -.05
    return {0,0,s,slots[side][1],0,.05,0,0,-s,0,0,0,0,0,0,1}
  end}
local scene={scene={host=host,actors=actors},world={actorSlots=slots,groundY=0},
  camera={eye={0,8,20},focus={0,2,0},up={0,1,0},
    projection={1,0,0,0,0,1.333,0,0,0,0,-1.002,-.2002,0,0,-1,0}}}
local findings,scenarios,failures={},0,0
local function record(move,scenario,d)
  local code=d.code or "audit-error"
  local row=findings[code]
  if not row then row={moves={},scenarios={},messages={}};findings[code]=row end
  if move then row.moves[move]=true end
  row.scenarios[scenario]=true
  row.messages[tostring(d.message or code)]=true
end
local function renderer(model)
  assert(model and model.prims,"missing model geometry")
  return {model=model,parts={},setHandlerRuntime=function()end,
    updatePose=function()end,release=function()end,
    drawScene=function(_,_,matrix)
      assert(type(matrix)=="table" and #matrix==16,"invalid draw matrix")
      for _,v in ipairs(matrix) do assert(v==v and math.abs(v)<math.huge,"nonfinite draw matrix") end
      return true
    end}
end
local preview=Preview.new({rom=rom,releaseModel=function()end,
  importer={newRendererFromModel=renderer}})
preview.catalog=catalog
-- Static coverage includes unselected branch records and unused programs.
local opcodes,programReferences={},{}
for id=0,394 do
  local p=catalog.programs[id]
  for _,r in ipairs(p.records) do opcodes[r.opcode]=(opcodes[r.opcode] or 0)+1 end
  for condition=0,2 do
    local execution=Native.execute(p,{moveId=0,condition=condition})
    for _,d in ipairs(execution.diagnostics or {}) do
      record(nil,"program-"..id,d)
    end
  end
end
for move=1,251 do
  for _,bank in ipairs({"primaryDispatch","alternateDispatch"}) do
    for _,route in ipairs(catalog.moves[move][bank]) do
      if route.programId then
        programReferences[route.programId]=true
        for _,command in ipairs(catalog.programs[route.programId].records) do
          local event=command.emitter
          if event and event.descriptorKind=="particle" then
            -- Static inspection has no actor. Supply an ordinary source scale
            -- so missing scene input is not counted as missing implementation.
            -- Ordinary move contexts return zero from the special lookup.
            local state=Motion.init({event=event,material=event.material,nativeSpawnScale=1,
              nativeContextScale=Dispatch.contextScale(move)})
            for _,d in ipairs(state.diagnostics) do
              if d.code=="unsupported-native-constructor-scale"
                  or d.code=="unsupported-native-hide-transition" then
                record(move,"static-"..move.."/"..bank,d)
              end
            end
          end
        end
      end
    end
  end
  if not staticOnly and (not selectedMove or move==selectedMove) then
  for _,alternate in ipairs({false,true}) do for _,side in ipairs({"player","enemy"}) do
    local scenario=("%03d/%s/%s"):format(move,alternate and "alternate" or "primary",side)
    scenarios=scenarios+1
    for actorSide,a in pairs(actors) do a.renderer.fxDispatchRow=actorSide==side and move-1 or 251 end
    local ok,err=xpcall(function()
      assert(preview:start(move,side,alternate,scene))
      for frame=0,ticks do
        if frame==120 then preview:finish() end
        if frame<3 or frame%stride==0 or frame==ticks then
          preview:draw(scene);preview.player:drawOverlay(scene)
        end
        if frame<ticks then preview:step() end
      end
    end,debug.traceback)
    if not ok then failures=failures+1;record(move,scenario,{code="audit-execution-error",message=err}) end
    if preview.player then
      for _,d in ipairs(preview.player.diagnostics) do record(move,scenario,d) end
      for _,d in ipairs(preview.player:snapshot().diagnostics or {}) do record(move,scenario,d) end
    end
    preview:release()
  end end
  end
  if not selectedMove and move%25==0 then io.stderr:write(("audited %d/251 moves\n"):format(move)) end
end
local function keys(t)local a={} for k in pairs(t)do a[#a+1]=k end table.sort(a);return a end
print("# Battle FX implementation audit")
print(("\n%d moves simulated; %d scenarios (both banks and both source sides); %d ticks each; draw samples every %d ticks; finish signal at tick 120."):format(staticOnly and 0 or selectedMove and 1 or 251,scenarios,ticks,stride))
print(("395 programs inspected, %d referenced by move dispatch; 30 lifecycle table rows; %d execution failures."):format(#keys(programReferences),failures))
print("Real Koffing/Croconaw ROM skeletons, bind-pose markers, dispatch profiles and FX resource extraction. Renderer is a CPU validation stub: GPU shaders, animated poses, timing between draw samples, other species, arenas and every battle-state combination are not verified.")
print("\nDiagnostics indicate unsupported or approximate paths; absence of diagnostics does not establish visual parity.")
print("\nStatic descriptor checks include all 251 moves and unselected branches. Context counts include static checks and runtime scenarios.")
print("\n| Diagnostic | Moves | Contexts |\n|---|---:|---:|")
for _,code in ipairs(keys(findings)) do
  local r=findings[code];print(("| %s | %d | %d |"):format(code,#keys(r.moves),#keys(r.scenarios)))
end
for _,code in ipairs(keys(findings)) do
  local r=findings[code];print("\n## "..code.."\n")
  for _,message in ipairs(keys(r.messages)) do print("- "..message:gsub("\n"," ")) end
  local moves={};for _,id in ipairs(keys(r.moves))do moves[#moves+1]=("%03d %s"):format(id,names[id])end
  print("\nMoves: "..(#moves>0 and table.concat(moves,", ") or "unused/unselected program paths only"))
end
print("\n## Opcode inventory\n")
for _,opcode in ipairs(keys(opcodes)) do print(("- Opcode %d: %d records"):format(opcode,opcodes[opcode])) end
for _,a in pairs(actors) do a.renderer:release() end
if failures>0 then os.exit(1) end
