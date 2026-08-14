-- Developer utility; excluded from releases and from the sandbox validator.
-- Run from the Gen1Recomp root:
--   luajit mods/STADIUM2_IMPORTER/tests/dump_glb.lua \
--     --rom mods/STADIUM2_IMPORTER/baseroms/stadium2.z64 \
--     --output mods/STADIUM2_IMPORTER/build/glb --species 25

package.path="./?.lua;./?/init.lua;"..package.path

local Rom=require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract=require("mods.STADIUM2_IMPORTER.lib.extract")
local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
local GLB=require("mods.STADIUM2_IMPORTER.lib.glb")

local function usage(message)
  if message then io.stderr:write("error: "..message.."\n\n") end
  io.stderr:write([[
Usage: luajit mods/STADIUM2_IMPORTER/tests/dump_glb.lua [options]

  --rom PATH          US Pokemon Stadium 2 ROM
  --output DIR        Destination directory (default: build/glb)
  --count N           Extract 151 or 251 species (default: 151)
  --species N         Write only one National Dex species (extraction still scans the bank)
  --variant VALUE     normal, shiny, or both (default: both)
  --validate-only     Encode every selected GLB without writing files
  --quiet             Print only the final result
  --help              Show this message
]])
  os.exit(message and 1 or 0)
end

local options={output="mods/STADIUM2_IMPORTER/build/glb",count=151,variant="both",
  validateOnly=false,quiet=false}
local at=1
while at<=#arg do
  local key=arg[at]
  if key=="--help" then usage()
  elseif key=="--validate-only" then options.validateOnly=true;at=at+1
  elseif key=="--quiet" then options.quiet=true;at=at+1
  elseif key=="--rom" or key=="--output" or key=="--count"
      or key=="--species" or key=="--variant" then
    if arg[at+1]==nil then usage(key.." needs a value") end
    local name=key:sub(3)
    options[name]=arg[at+1]
    at=at+2
  else usage("unknown option "..tostring(key)) end
end
options.count=math.floor(tonumber(options.count) or 0)
options.species=options.species and math.floor(tonumber(options.species) or 0) or nil
if not options.rom then usage("--rom is required") end
if options.count~=151 and options.count~=251 then usage("--count must be 151 or 251") end
if options.species and (options.species<1 or options.species>options.count) then
  usage("--species is outside the selected count")
end
if options.variant~="normal" and options.variant~="shiny" and options.variant~="both" then
  usage("--variant must be normal, shiny, or both")
end

local function quote(value)
  return "'"..tostring(value):gsub("'","'\\''").."'"
end

local function readFile(path)
  local file,err=io.open(path,"rb")
  if not file then return nil,err end
  local bytes=file:read("*a")
  file:close()
  return bytes
end

local function writeFile(path,bytes)
  local file,err=io.open(path,"wb")
  if not file then return nil,err end
  local ok,writeErr=file:write(bytes)
  file:close()
  if not ok then return nil,writeErr end
  return true
end

local rom,readErr=readFile(options.rom)
if not rom then usage("could not read ROM: "..tostring(readErr)) end
local normalized,meta=Rom.validate(rom)
if not normalized then usage("ROM validation failed: "..tostring(meta)) end
if not options.validateOnly then
  local mkdirOK=os.execute("mkdir -p "..quote(options.output))
  if mkdirOK~=true and mkdirOK~=0 then usage("could not create output directory") end
end

local written,totalBytes=0,0
local function selected(species,variant)
  return (not options.species or options.species==species)
    and (options.variant=="both" or options.variant==variant)
end

local function dump(bytes,name,variant)
  local model,parseErr=Pack.parse(bytes)
  if not model then error(parseErr,0) end
  model.variant=variant
  local glb,summary=GLB.encode(model,{name=name,variant=variant})
  if not glb then error(summary,0) end
  local path=options.output.."/"..name..".glb"
  if not options.validateOnly then
    local ok,err=writeFile(path,glb)
    if not ok then error("could not write "..path..": "..tostring(err),0) end
  end
  written,totalBytes=written+1,totalBytes+#glb
  if not options.quiet then
    io.write(("GLB %-30s %8d bytes  prim=%d bone=%d anim=%d\n")
      :format(name,#glb,summary.primitives,summary.bones,summary.animations))
  end
end

Extract.configure({count=options.count})
local job=Extract.newJob(normalized,function(species,normalBytes,shinyBytes)
  if selected(species,"normal") then
    dump(normalBytes,("%03d-normal"):format(species),"normal")
  end
  if selected(species,"shiny") then
    dump(shinyBytes,("%03d-shiny"):format(species),"shiny")
  end
  return true
end,function(name,bytes)
  if not options.species then
    local variant=name:find("_shiny$",1,false) and "shiny" or "normal"
    if options.variant=="both" or options.variant==variant then
      dump(bytes,name:gsub("_","-"),variant)
    end
  end
  return true
end)

while true do
  local ok,more=pcall(job.step,job)
  if not ok then error(more,0) end
  if more==false then break end
end
if not job.success then error(job.error or job.lastError or "Stadium extraction failed",0) end
io.write(("DONE models=%d bytes=%d output=%s rom=%s\n")
  :format(written,totalBytes,options.validateOnly and "validated-only" or options.output,
    tostring(meta.title or "Pokemon Stadium 2")))
