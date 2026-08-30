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
  -- Translucent arena art (including authored shadow cards) is composited
  -- after the opaque field. It must never replace the floor's depth. A ROM
  -- graph-layer rank accepts equal depth because its vertex bias preserves
  -- the authored submission order; legacy packs may supply the same field
  -- from the geometric fallback.
  if type(prim) == "table" and (prim.arenaAlphaMode == "blend"
      or prim.arenaCompositeMode == "shadow") then
    return prim.coplanarLayer and RenderContract.DECAL_DEPTH_COMPARE
      or RenderContract.MODEL_DEPTH_COMPARE, false
  end
  -- Opaque/cutout arena layers are a real surface stack, not translucent
  -- model decals. Each ranked layer writes its biased depth so the next layer
  -- composes against one deterministic surface instead of all three sharing
  -- the original floor depth.
  if type(prim) == "table" and prim.coplanarLayer
      and (prim.arenaAlphaMode == "opaque"
        or prim.arenaAlphaMode == "cutout") then
    return RenderContract.DECAL_DEPTH_COMPARE, writeEnabled ~= false
  end
  -- Modern arena cutouts are opaque geometry with discarded texels. They
  -- must establish depth like a fence or floor edge; treating every alpha
  -- texture as a no-write decal lets later arena assemblies bleed through.
  if type(prim) == "table" and prim.arenaAlphaMode == "cutout"
      and not prim.coplanarLayer then
    return RenderContract.MODEL_DEPTH_COMPARE, writeEnabled ~= false
  end
  if type(prim) == "table" and (prim.decal == true
      or (tonumber(prim.coplanarLayer) or 0) > 0
      or prim.coplanarLayer == true)
      and not prim.callbackTextureRequired and prim.sourceTextureMissing == false then
    return RenderContract.DECAL_DEPTH_COMPARE, false
  end
  return RenderContract.MODEL_DEPTH_COMPARE, writeEnabled ~= false
end

return RenderContract
