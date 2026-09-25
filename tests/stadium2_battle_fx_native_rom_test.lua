local Rom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Native=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")
local Objects=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_objects")
local Resources=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources")
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("SKIP: native callbacks ROM unavailable");return
end
local rom=file:read("*a");file:close()
local catalog=assert(Rom.catalog(rom))
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
-- Constructor flags were previously mistaken for allocation sizes. Guard
-- the actual instructions before accepting screen-space geometry.
check(Rom.read32(rom,0x841078EC)==0x24057028,"screen constructor sets flags 0x7028")
check(Rom.read32(rom,0x84107904)==0x3C014320,"screen center is 160, not 40")
check(Rom.read32(rom,0x84103308)==0x8C4E0004,"screen draw loads export90 resource entries")
local counts={}
for id=1,251 do
  local seen={}
  for _,pid in ipairs({catalog.moves[id].primary,catalog.moves[id].alternate}) do
    for _,r in ipairs(catalog.programs[pid] and catalog.programs[pid].records or {}) do
      local e=r.emitter
      if e and e.descriptorKind=="native-object" then seen[e.mode]=true end
    end
  end
  for mode in pairs(seen) do counts[mode]=(counts[mode] or 0)+1 end
end
check(counts[2]==104 and counts[5]==89 and counts[8]==51,
  "retail native-object route coverage remains 104/89/51")
check(not counts[4] and not counts[6],"unused modes are not counted as retail coverage")
local descriptors={}
for _,program in pairs(catalog.programs) do
  for _,record in ipairs(program.records) do
    local emitter=record.emitter
    if emitter and emitter.descriptorKind=="native-object" then
      descriptors[emitter.commandPointer]=record
    end
  end
end
local count=0
for pointer,record in pairs(descriptors) do
  local execution=Native.execute({records={record}},{sourceSide="enemy"})
  local event=execution.scheduled[1];event.context={sourceSide="enemy"}
  local manager=Objects.new()
  assert(manager:enqueue(pointer,event))
  manager:tick(512)
  check(#manager:snapshot().diagnostics==0,
    ("native descriptor 0x%08X must execute without unsupported callbacks"):format(pointer))
  count=count+1
end
local modelRecord
for _,pid in ipairs({catalog.moves[5].primary,catalog.moves[5].alternate}) do
  for _,r in ipairs(catalog.programs[pid].records) do
    if r.emitter and r.emitter.mode==5 then modelRecord=r;break end
  end
  if modelRecord then break end
end
local event=Native.execute({records={assert(modelRecord)}},{}).scheduled[1]
event.context={sourceSide="enemy"}
local manager=Objects.new();assert(manager:enqueue(event.commandPointer,event))
manager:tick(4)
check(manager:snapshot().modelColors.enemy.color[4]==255,"Mega Punch model flash starts after ROM delay4")
manager:tick(3)
check(manager:snapshot().modelColors.enemy.color[4]==145,"Mega Punch model flash follows exact truncated ROM keys")
manager:tick(5)
check(manager:snapshot().modelColors.enemy.color[4]==0,"Mega Punch restores model blend at the final key")
local shape=assert(Resources.shapeFromResolved(assert(Resources.resolve(rom,{})),90))
local model=assert(Resources.modelFromShape(shape))
check(shape.geometryMode==5 and #model.prims==1 and #model.textures==0,
  "screen overlay loads the actual untextured 2D export")
local pos=model.prims[1].pos
check(pos[1]==-160 and pos[2]==120 and pos[7]==160 and pos[8]==-120,
  "export90 is the authored 320x240 screen quad")
print(("%d checks passed (native callbacks: %d ROM descriptors)"):format(checks,count))
