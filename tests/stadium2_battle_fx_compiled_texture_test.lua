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
  else
    callbackParts = callbackParts + 1
    ok(prim.callbackTextureRequired == true, "guard/blade nodes are callback textured")
    ok(swords.textures[renderer:currentTexture(prim)].callback == true,
      "guard/blade nodes bind the callback texture")
    ok(math.floor((prim.geometryMode or 0) / 0x40000) % 2 == 1,
      "guard/blade nodes receive the callback texture-gen state")
  end
end
ok(grips == 1 and callbackParts == 11, "one grip primitive and eleven callback parts")
renderer:release()
print(checks .. " checks passed (battle FX compiled textures)")
