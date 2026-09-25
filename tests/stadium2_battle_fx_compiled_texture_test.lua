-- Battle-FX texture decoding: intensity alpha for I formats and the
-- Swords Dance callback-texture ownership. Run from the Gen1Recomp root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local path = os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(path, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1", "required ROM unavailable")
  print("SKIP battle FX compiled textures (ROM unavailable)")
  return
end
local rom = file:read("*a"); file:close()
local FxRom = require(prefix .. "stadium2_battle_fx_rom")
local Resources = require(prefix .. "stadium2_battle_fx_resources")
local Fragment = require(prefix .. "fragment")
local Renderer = require(prefix .. "renderer")
local catalog = assert(FxRom.catalog(rom))
local slice = rom:sub(Resources.ROM_START + 1, Resources.ROM_END)

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end
local function model(moveId, shapeId, animationId)
  local resources = assert(Resources.resolve(slice, catalog.moves[moveId].resources))
  local shape = assert(Resources.shapeFromResolved(resources, shapeId, animationId))
  return assert(Resources.modelFromShape(shape, "texture-test")), shape
end

-- RDP I formats replicate intensity into alpha (Take Down streaks, shape 188).
local streaks, streakShape = model(36, 188, 189)
local sawIntensity = false
local swordsGrip = model(14, 140)
local selectorOne = false
for _, prim in ipairs(swordsGrip.prims) do
  local c = prim.material and prim.material.combiner
  if prim.callbackOffset == nil and c
      and table.concat(c.color0, ",") == "1,31,3,31"
      and table.concat(c.color1, ",") == "0,31,4,31" then selectorOne = true end
end
ok(selectorOne, "a Swords Dance grip uses table combiner 1")
for _, texture in ipairs(streaks.textures) do
  if (texture.format or texture.fmt) == 4 then
    for i = 1, #texture.rgba, 4 do
      local l, a = texture.rgba:byte(i), texture.rgba:byte(i + 3)
      assert(l == a, "FX I-format texel alpha equals its intensity")
      if l < 255 then sawIntensity = true end
    end
  end
end
ok(sawIntensity, "FX I4 textures keep sub-opaque intensity alpha")
Fragment.setBase(Resources.VRAM_BASE)
local opaque = assert(Fragment.extract(streakShape._module, "opaque-default",
  {directLayoutOffset = streakShape.layoutOffset, bakePhase5Geometry = true}))
for _, texture in ipairs(opaque.textures) do
  if texture.fmt == 4 and type(texture.rgba) == "string" then
    for i = 4, #texture.rgba, 4 do assert(texture.rgba:byte(i) == 255) end
  end
end
ok(true, "model imports keep the opaque I-format decode")

-- Display-list RDP state (FX layouts track it): Gust's wind sheet uses the
-- combiner its node list sets; a Swords Dance grip the table combiner that
-- 8003D888 submits for its 0x23 selector (1: TEXEL0 * PRIM, lit).
local Phase5 = require(prefix .. "render_callbacks.phase5_geometry")
local gust = model(16, 142)
for _, prim in ipairs(gust.prims) do
  local combiner = prim.material and prim.material.combiner
  ok(prim.material and prim.material.displayListState == true, "wind sheet carries list state")
  ok(combiner and table.concat(combiner.selectors, ",")
    == table.concat(Phase5.combinerFromWords(0x272C60, 0x150C937F).selectors, ","),
    "wind sheet uses its list combiner FC272C60 150C937F")
  ok(prim.battleFxNodeLayer == 9, "wind sheet keeps its node layer")
end
local RenderMode = require(prefix .. "stadium2_battle_fx_render_mode")
local layer9 = RenderMode.fromNodeLayer(9)
ok(layer9.blend == "blend" and layer9.depthWrite == false and layer9.depthCompare == true,
  "layer 9 blends without depth writes")

-- Swords Dance: six swords. The grip node authors texture 1 through 0x23;
-- every guard/blade node draws with its own 0x81000138 callback texture.
local swords = model(14, 140, 141)
local renderer = assert(Renderer.new(swords, {flipY = false}))
renderer:setHandlerRuntime({callbackFrame = 10, materialFrame = 10}, false)
local grips, callbackParts = 0, 0
for _, prim in ipairs(swords.prims) do
  if prim.callbackOffset == nil then
    grips = grips + 1
    ok(renderer:currentTexture(prim) == 1, "grips keep their authored texture")
    ok(prim.material and prim.material.combiner, "grips carry an RDP combiner")
  else
    callbackParts = callbackParts + 1
    ok(prim.callbackTextureRequired == true, "guard/blade nodes are callback textured")
    ok(swords.textures[renderer:currentTexture(prim)].callback == true,
      "guard/blade nodes bind the callback texture")
    ok(math.floor((prim.geometryMode or 0) / 0x40000) % 2 == 1,
      "guard/blade nodes receive the callback texture-gen state")
  end
end
-- Grip draws split by inherited RDP state: most follow a flag-4 reset to
-- the 0x23 selector-1 combiner, one keeps the preceding blade list's.
ok(grips == 2 and callbackParts == 11, "two grip primitives and eleven callback parts")
renderer:release()
print(checks .. " checks passed (battle FX compiled textures)")
