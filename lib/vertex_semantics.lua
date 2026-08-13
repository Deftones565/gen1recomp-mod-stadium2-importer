-- Stadium 2's model display lists do not use G_LIGHTING as a reliable Vtx
-- layout discriminator.  In ordinary model geometry the final three Vtx
-- bytes are signed normals (whose encoded length is about 119), even though
-- the local geometry mode commonly contains only G_CULL_BACK.  Callback and
-- emissive geometry instead uses those bytes as RGB.  Keep this decision in
-- one place so extractors, audits, and future handler families agree.
local VertexSemantics = {}

local function lengthAt(normals, i)
  local x, y, z = normals[i] or 0, normals[i + 1] or 0, normals[i + 2] or 0
  return math.sqrt(x * x + y * y + z * z)
end

function VertexSemantics.measure(normals)
  local out = { vertices = 0, normalLike = 0, zeroLike = 0, meanLength = 0 }
  for i = 1, #(normals or {}), 3 do
    local length = lengthAt(normals, i)
    out.vertices = out.vertices + 1
    out.meanLength = out.meanLength + length
    -- Authored normals in this ROM cluster at 118/127..120/127.  Leave a
    -- little tolerance for quantisation without mistaking literal mid-grey
    -- vertex colours (for example Beedrill's 55,55,55) for normals.
    if length >= 0.85 and length <= 1.05 then out.normalLike = out.normalLike + 1 end
    if length <= 0.10 then out.zeroLike = out.zeroLike + 1 end
  end
  if out.vertices > 0 then
    out.normalRatio = out.normalLike / out.vertices
    out.zeroRatio = out.zeroLike / out.vertices
    out.meanLength = out.meanLength / out.vertices
  else
    out.normalRatio, out.zeroRatio = 0, 0
  end
  return out
end

function VertexSemantics.classify(normals)
  local measure = VertexSemantics.measure(normals)
  -- Some draw batches contain a small number of zeroed callback vertices in
  -- addition to authored normals.  A majority vote keeps their model surface
  -- lit while all-zero particle/billboard batches remain vertex-coloured.
  local semantics = measure.normalRatio >= 0.50 and "normal" or "color"
  return semantics, measure
end

return VertexSemantics
