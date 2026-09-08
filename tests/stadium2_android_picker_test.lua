package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

package.loaded["mods.STADIUM2_IMPORTER.lib.importer"]=nil
package.loaded["mods.STADIUM2_IMPORTER.lib.cache"]=nil
package.loaded["mods.STADIUM2_IMPORTER.lib.discovery"]=nil
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local Cache=Importer.cache
local records={}
local rom="stadium2-rom"
local mod={game={save={version="red",meta={playthroughId="test"}}}}
function mod:read(path)
  if path=="stadium2.z64" then return rom end
end
mod.storage={}
function mod.storage:context(game)
  return game and {gameVersion="red",playthroughId="test"} or nil
end
function mod.storage:write(game,key,value) records[key]=value;return true end
function mod.storage:read(game,key) return records[key] end
function mod.storage:list(game,prefix)
  local out={}
  prefix=prefix or ""
  for key in pairs(records) do
    if prefix=="" or key==prefix or key:sub(1,#prefix+1)==prefix.."/" then
      out[#out+1]=key
    end
  end
  table.sort(out)
  return out
end
function mod.storage:delete(game,key)
  if records[key]==nil then return false,"not_found" end
  records[key]=nil;return true
end

Importer.bind(mod)
Importer.setPlaythroughReady(true)
ok(Cache.writePair(1,"normal-pack","shiny-pack"),
  "binary model packs write through scoped mod.storage")
ok(Cache.read(1,"normal")=="normal-pack" and Cache.read(1,"shiny")=="shiny-pack",
  "binary model packs round-trip through scoped mod.storage")
ok(Cache.writeSpecial("substitute","special-pack")
  and Cache.readSpecial("substitute")=="special-pack",
  "special model packs use the same scoped storage")
for species=2,151 do
  ok(Cache.writePair(species,"normal-pack","shiny-pack"),
    "complete sandbox cache includes species "..species)
end
ok(Cache.finish({md5="fixture",title="fixture",byteOrder="z64"},151),
  "completion marker writes after model records")
ok(Cache.available(151) and not Cache.available(251),
  "sandbox cache marker preserves configured species count")

local selectedBytes,selectedLabel
Importer.beginFrom=function(bytes,label)
  selectedBytes,selectedLabel=bytes,label
  return true
end
local started,err=Importer.request()
ok(started,err or "mod-owned ROM input starts")
ok(selectedBytes==rom and selectedLabel=="stadium2.z64",
  "ROM bytes come only from mod:read")
ok(Importer.nativePickerAvailable==nil and Importer.NATIVE_PICKED==nil,
  "sandbox build exposes no raw platform picker or handoff path")

mod.read=function() return nil end
local missing,missingErr=Importer.request()
ok(not missing and tostring(missingErr):find("Imported Files panel",1,true),
  "missing required import points to the engine-managed ROM panel")

ok(Cache.clear(251),"sandbox cache can be cleared through mod.storage")
ok(not Cache.available(151),"clearing removes the completion marker")

print(("%d checks passed (Stadium 2 sandbox storage/import)"):format(checks))
