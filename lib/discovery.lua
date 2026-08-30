-- Stadium ROM discovery under the engine mod sandbox. Only files packaged
-- inside this mod may be named; external selection needs a future scoped
-- engine picker API.
local Discovery = {}

local NAMES = {
  "Pokemon Stadium 2 (USA).z64",
  "Pokemon Stadium 2 (USA).n64",
  "Pokemon Stadium 2 (USA).v64",
  "pokemon_stadium_2.z64",
  "pokemonstadium2.z64",
  "stadium2.z64",
}

local modRef

function Discovery.bind(mod)
  modRef=mod
  return Discovery
end

local function readOwn(path)
  if not (modRef and type(modRef.read)=="function") then return nil end
  local ok,bytes=pcall(modRef.read,modRef,path)
  if ok and type(bytes)=="string" and bytes~="" then return bytes end
  return nil
end

function Discovery.find()
  for _,name in ipairs(NAMES) do
    for _,prefix in ipairs({"","baseroms/"}) do
      local path=prefix..name
      local bytes=readOwn(path)
      if bytes then return {kind="mod",path=path,bytes=bytes} end
    end
  end
  return nil
end

function Discovery.read(candidate)
  if not candidate then return nil,"no Stadium 2 ROM found inside the mod" end
  local bytes=candidate.bytes or readOwn(candidate.path)
  if type(bytes)~="string" or bytes=="" then
    return nil,"could not read the mod-owned Stadium 2 ROM"
  end
  return bytes
end

function Discovery.choose()
  return nil,"the engine sandbox has no scoped external ROM picker"
end

Discovery.names=NAMES

return Discovery
