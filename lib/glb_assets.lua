-- Sandboxed discovery for optional edited GLBs packaged inside the mod.
local Assets={}
local modRef

function Assets.bind(mod) modRef=mod;return Assets end

local function read(path)
  if not (modRef and type(modRef.read)=="function") then return nil end
  local ok,bytes=pcall(modRef.read,modRef,path)
  if ok and type(bytes)=="string" and bytes:sub(1,4)=="glTF" then return bytes,path end
  return nil
end

function Assets.speciesPaths(species,variant)
  species=math.floor(tonumber(species) or 0)
  variant=variant=="shiny" and "shiny" or "normal"
  local dex=("%03d"):format(species)
  return {("models/%s-%s.glb"):format(dex,variant),
    ("models/%s/%s.glb"):format(variant,dex)}
end

function Assets.specialPaths(name)
  name=tostring(name or ""):gsub("[^%w_-]","")
  local dashed=name:gsub("_","-")
  return {"models/"..name..".glb","models/"..dashed..".glb",
    "models/special/"..name..".glb","models/special/"..dashed..".glb"}
end

local function first(paths)
  for _,path in ipairs(paths) do
    local bytes,found=read(path)
    if bytes then return bytes,found end
  end
  return nil
end

function Assets.readSpecies(species,variant)
  return first(Assets.speciesPaths(species,variant))
end

function Assets.readSpecial(name)
  return first(Assets.specialPaths(name))
end

return Assets
