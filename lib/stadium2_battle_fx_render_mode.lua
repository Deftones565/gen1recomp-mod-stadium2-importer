-- Per-draw-entry RDP render mode for direct battle-FX shapes.
--
-- 841031F4 calls 84102E84 with shape entry +6 after the material callback and
-- before the entry display list. 84102E84 emits one G_SETOTHERMODE_L
-- (E200001C) word selected by the low six bits and by flags 0x40/0x80:
-- variant = (0x40 ? 1 : 0) + (0x80 ? 2 : 0). Low value 0x3F instead binds
-- the owner battler's texture through 84102D38.
local RenderMode = {}

local WORDS = {
  -- Low 1: blender CLR_IN pass/CLR_IN,A_IN,CLR_MEM,A_MEM (opaque surfaces).
  [1] = {0x0F0A4000, 0x0C192048, 0x0C192230, 0x0C192078},
  -- Low 4: coverage-times-alpha edge (cutout) surfaces.
  [4] = {0x0F0A7008, 0x0C193048, 0x0C193078, 0x0C193078},
  -- Low 6: translucent CLR_IN,A_IN,CLR_MEM,1MA surfaces.
  [6] = {0x0C184240, 0x0C1841C8, 0x0C184A50, 0x0C1849D8},
}
-- Every other low value falls through to 841031BC.
local DEFAULT_WORD = 0x0C184240

local Z_CMP, Z_UPD = 0x10, 0x20
local CVG_X_ALPHA, ALPHA_CVG_SEL = 0x1000, 0x2000

local function has(value, flag)
  return math.floor(value / flag) % 2 == 1
end

-- Returns nil for a missing render state (compiled layouts, other sources).
function RenderMode.decode(renderState)
  renderState = tonumber(renderState)
  if not renderState then return nil end
  renderState = math.floor(renderState) % 0x10000
  local low = renderState % 0x40
  local variant = (has(renderState, 0x40) and 1 or 0)
    + (has(renderState, 0x80) and 2 or 0)
  if low == 0x3F then
    return {renderState = renderState, low = low, variant = variant,
      ownerTexture = true}
  end
  local row = WORDS[low]
  local word = row and row[variant + 1] or DEFAULT_WORD
  local function field(shift) return math.floor(word / 2 ^ shift) % 4 end
  -- Cycle-2 blender inputs: P bits 28-29, A 24-25, M 20-21, B 16-17.
  local p2, a2, m2, b2 = field(28), field(24), field(20), field(16)
  local blend
  if has(word, ALPHA_CVG_SEL) and has(word, CVG_X_ALPHA) then
    -- Coverage is replaced by coverage x alpha. A texel whose alpha yields no
    -- 3-bit coverage (alpha < 32/255) is not written; others write color.
    blend = "cutout"
  elseif p2 == 0 and a2 == 0 and m2 == 1 and b2 == 0 then
    -- CLR_IN * A_IN + CLR_MEM * (1 - A_IN).
    blend = "blend"
  else
    blend = "opaque"
  end
  return {
    renderState = renderState,
    low = low,
    variant = variant,
    word = word,
    blend = blend,
    depthCompare = has(word, Z_CMP),
    depthWrite = has(word, Z_UPD),
  }
end

-- Compiled-layout (model) visuals: 8003D888 selects the render mode from
-- the node's submission layer through the 8003CC14 table (Materials). The
-- blender and depth-update bits agree across all six root profiles; depth
-- compare is set only in the odd (Z-buffered) profiles, which the battle
-- scene uses since its Pokemon models are depth tested.
function RenderMode.fromNodeLayer(layer)
  layer = tonumber(layer)
  if not layer then return nil end
  local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
  local word = Materials.layerRenderMode(1, layer)
  if not word then return nil end
  local function field(shift) return math.floor(word / 2 ^ shift) % 4 end
  local p2, a2, m2, b2 = field(28), field(24), field(20), field(16)
  local blend = (p2 == 0 and a2 == 0 and m2 == 1 and b2 == 0) and "blend" or "opaque"
  if has(word, ALPHA_CVG_SEL) and has(word, CVG_X_ALPHA) then blend = "cutout" end
  return {
    nodeLayer = layer,
    word = word,
    blend = blend,
    depthCompare = has(word, Z_CMP),
    depthWrite = has(word, Z_UPD),
  }
end

-- Lowest alpha that produces non-zero coverage for cutout entries.
RenderMode.CUTOUT_ALPHA = 32 / 255

return RenderMode
