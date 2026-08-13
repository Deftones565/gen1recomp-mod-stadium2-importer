-- Renderer-facing state that is part of Stadium's model format contract.
-- Keep it separate from the drawing implementation so parity audits can
-- verify these semantics without constructing a GPU renderer.
local RenderContract = {
  MODEL_DEPTH_COMPARE = "less",
  DECAL_DEPTH_COMPARE = "lequal",
  DYNAMIC_DEPTH_COMPARE = "less",
  SHADOW_DEPTH_COMPARE = "less",
}

-- Later model primitives include coplanar texture decals such as eyes,
-- pupils, shell markings and wing details. They rely on display-list order:
-- equal depth must pass so the later authored layer remains visible.
function RenderContract.supportsCoplanarDecals()
  return RenderContract.MODEL_DEPTH_COMPARE == "less"
    and RenderContract.DECAL_DEPTH_COMPARE == "lequal"
end

function RenderContract.depthState(prim, writeEnabled)
  if type(prim) == "table" and prim.decal == true
      and not prim.callbackTextureRequired and prim.sourceTextureMissing == false then
    return RenderContract.DECAL_DEPTH_COMPARE, false
  end
  return RenderContract.MODEL_DEPTH_COMPARE, writeEnabled ~= false
end

return RenderContract
