local Mat = require("mods.STADIUM2_IMPORTER.lib.renderer")

local Shadow = { resolution=1024, dark=.68, bias=.003 }
local color, depth, allocated
local strength = 1
local unpack = table.unpack or unpack
local TO_UNIT = { .5,0,0,.5, 0,.5,0,.5, 0,0,.5,.5, 0,0,0,1 }

local function release(item)
  if item and item.release then pcall(item.release, item) end
end

local function ensure()
  local g = love and love.graphics
  if not g then return false end
  if color and allocated == Shadow.resolution then return true end
  release(color); release(depth)
  local ok, c = pcall(g.newCanvas, Shadow.resolution, Shadow.resolution,
    {format="rgba8",readable=true,dpiscale=1})
  if not ok then return false end
  local dok, d = pcall(g.newCanvas, Shadow.resolution, Shadow.resolution,
    {format="depth24stencil8",readable=false,dpiscale=1})
  if not dok then release(c); return false end
  c:setFilter("nearest", "nearest")
  pcall(c.setWrap, c, "clamp", "clamp")
  color, depth, allocated = c, d, Shadow.resolution
  return true
end

function Shadow.begin(lightDir, shadowStrength)
  if not ensure() then return nil end
  local g = love.graphics
  Shadow.previous = g.getCanvas and {g.getCanvas()} or nil
  g.setCanvas({color,depthstencil=depth})
  g.clear(1,1,1,1,true,true)
  if g.setDepthMode then g.setDepthMode("less",true) end
  if g.setBlendMode then g.setBlendMode("replace","premultiplied") end
  local d = lightDir or {-.85,-1,-.55}
  strength=math.max(0,math.min(1,tonumber(shadowStrength) or 1))
  local n = math.sqrt(d[1]^2+d[2]^2+d[3]^2)
  d = {d[1]/n,d[2]/n,d[3]/n}
  local view = Mat.lookAt(-d[1]*90,-d[2]*90,-d[3]*90,0,4,0)
  Shadow.clipVP = Mat.matMul(Mat.ortho(-58,58,-58,58,1,190),view)
  Shadow.uvVP = Mat.matMul(TO_UNIT,Shadow.clipVP)
  return Shadow.clipVP
end

function Shadow.finish()
  local g, previous = love.graphics, Shadow.previous
  if previous and #previous > 0 then pcall(g.setCanvas,unpack(previous))
  else pcall(g.setCanvas) end
  Shadow.previous = nil
  if g.setBlendMode then pcall(g.setBlendMode,"alpha","alphamultiply") end
  return {map=color,sunVP=Shadow.uvVP,sunDark=Shadow.dark*strength,
    sunBias=Shadow.bias,sunTexel={1/Shadow.resolution,1/Shadow.resolution}}
end

function Shadow.release()
  release(color); release(depth)
  color, depth, allocated = nil, nil, nil
end

return Shadow
