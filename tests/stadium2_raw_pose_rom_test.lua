package.path="./?.lua;./?/init.lua;"..package.path
-- Raw pose clips decode with the footer's own file-offset header, including
-- static clips (Articuno clip 11), and authored negative scales (Dugtrio's
-- Dig clips hide the heads with -1) reach the skeleton unclamped.
local path=os.getenv("STADIUM2_ROM") or arg[1]
if not path then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 luajit "
    .."mods/STADIUM2_IMPORTER/tests/stadium2_raw_pose_rom_test.lua\n")
  os.exit(2)
end
local P="mods.STADIUM2_IMPORTER.lib."
local Rom=require(P.."rom")
local Extract=require(P.."extract")
local Fragment=require(P.."fragment")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local f=assert(io.open(path,"rb"))
local rom=Rom.normalise(f:read("*a"))
f:close()
local models=Extract.archiveAt(rom,Extract.MODEL_TABLE_START)

local function clips(species)
  local data=Rom.decompress(Rom.recordBytes(rom,models.records[species+1]))
  local info=Extract.fragmentInfo(data)
  Fragment.setBase(info.sourceBase)
  local model=Fragment.extract(Extract.runtimeModelFragment(data),"model.bin")
  return (Extract.animationBankForSpecies(rom,species,model.bones))
end

local function scaleRange(anim)
  local low,high=math.huge,-math.huge
  for _,track in pairs(anim.tracks) do
    for axis=1,3 do
      local s=track.s[axis]
      for _,v in ipairs(type(s)=="table" and s or {s}) do
        low,high=math.min(low,v),math.max(high,v)
      end
    end
  end
  return low,high
end

local articuno=clips(144)
ok(#articuno==11,"Articuno has 11 clips")
local still=articuno[11]
ok(still.pointerMode=="file-offset" and still.frames==2,
  "Articuno clip 11 is its 2-frame static pose, read with file offsets")
local low,high=scaleRange(still)
ok(low>0 and high<=1,"Articuno clip 11 keeps its authored 0.5-1.0 bone scales")
for i,anim in ipairs(articuno) do
  ok(anim.pointerMode=="file-offset","Articuno clip "..i.." uses file offsets")
end

local dugtrio=clips(51)
low=scaleRange(dugtrio[4])
ok(low<=-1,"Dugtrio's Dig clip carries the ROM's negative head scales")

print(("%d checks passed (raw pose ROM)"):format(checks))
