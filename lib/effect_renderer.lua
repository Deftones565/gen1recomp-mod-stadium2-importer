local DynamicObject = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object")

local EffectRenderer = {}

function EffectRenderer.billboardGeometry(particle, anchor, sourceGeometry, textureWidth, textureHeight)
  particle = type(particle) == "table" and particle or {}
  anchor = type(anchor) == "table" and anchor or {0,0,0}
  sourceGeometry = type(sourceGeometry) == "table" and sourceGeometry or {}
  local x, y, z
  if particle.absolute then
    x, y, z = tonumber(particle.x) or 0, tonumber(particle.y) or 0, tonumber(particle.z) or 0
  else
    x = (tonumber(anchor[1]) or 0) + (tonumber(particle.x) or 0)
    y = (tonumber(anchor[2]) or 0) + (tonumber(particle.y) or 0)
    z = (tonumber(anchor[3]) or 0) + (tonumber(particle.z) or 0)
  end
  local sx = (tonumber(particle.sx) or tonumber(particle.scale) or 1) * .1
  local sy = (tonumber(particle.sy) or tonumber(particle.scale) or 1) * .1
  local sz = (tonumber(particle.sz) or tonumber(particle.scale) or 1) * .1
  local source = sourceGeometry.vertices
  if type(source) ~= "table" or #source ~= 4 then
    source = {{x=-50,y=-50,z=0,s=0,t=1024},{x=50,y=-50,z=0,s=1024,t=1024},
      {x=50,y=50,z=0,s=1024,t=0},{x=-50,y=50,z=0,s=0,t=0}}
  end
  local tw, th = math.max(1, tonumber(textureWidth) or 32), math.max(1, tonumber(textureHeight) or 32)
  local vertices = {}
  for i = 1, 4 do
    local v = source[i]
    local vx,vy,vz = tonumber(v.x or v[1]) or 0,tonumber(v.y or v[2]) or 0,tonumber(v.z or v[3]) or 0
    local vs,vt = tonumber(v.s or v[4]) or 0,tonumber(v.t or v[5]) or 0
    vertices[i] = {x+vx*sx,y+vy*sy,z+vz*sz,(vs/32)/tw,(vt/32)/th}
  end
  local indices = sourceGeometry.indices
  if type(indices) ~= "table" or #indices ~= 6 then indices={1,2,3,1,3,4} end
  return {center={x,y,z},scale={sx,sy,sz},sourceVertices=source,vertices=vertices,indices=indices}
end

function EffectRenderer.materialState(species, age, runtime)
  local state, err = DynamicObject.renderState(species, age, runtime)
  if not state then return nil, err end
  state.effectIntensityMode = state.intensity and 1 or 0
  return state
end

function EffectRenderer.packet(effect, particle, anchor, textureWidth, textureHeight, runtime)
  local material, err = EffectRenderer.materialState(effect and effect.species, particle and particle.age, runtime)
  if not material then return nil, err end
  local slots = effect.textureSlots or {}
  local frame = #slots > 0 and math.max(1, math.min(#slots, material.frame or 1)) or nil
  return {
    kind="billboard-particle", geometry=EffectRenderer.billboardGeometry(particle, anchor,
      effect.geometry, textureWidth, textureHeight), material=material,
    textureIndex=frame and slots[frame] or nil,
    blend="alpha", depthWrite=false, cull=false, castsShadow=false,
  }
end

return EffectRenderer
