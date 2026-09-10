local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
local TextureParity = require("mods.STADIUM2_IMPORTER.lib.texture_parity")
local Flame = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.flame")
local Palette = require("mods.STADIUM2_IMPORTER.lib.palette")

local Pack = {}
Pack.SUBSTITUTE_SPECIES = 252
Pack.UNOWN_FORM_FIRST = 254
Pack.UNOWN_FORM_LAST = 278

Pack.CONTEXTS = {
  "idle", "entrance", "faint", "hit",
  "rom_context_255", "rom_context_256", "rom_context_257",
  "rom_context_258", "rom_context_259", "rom_context_260",
  "rom_context_261", "rom_context_262", "rom_context_263",
  "rom_context_264", "rom_context_265", "rom_context_266",
  "rom_context_267", "sleep", "rom_context_269",
  "rom_context_270",
}
Pack.N_MOVES = 251
Pack.LEGACY_N_MOVES = 165
Pack.NONE = 0xFFFF
Pack.FPS = 30

local byte = string.byte
local floor = math.floor

local Reader = {}
Reader.__index = Reader

local function need(self, n)
  if self.p + n - 1 > self.limit then error("truncated DSM4 pack", 0) end
end

function Reader:u8()
  need(self, 1)
  local v = byte(self.s, self.p)
  self.p = self.p + 1
  return v
end

function Reader:i8()
  local v = self:u8()
  if v >= 0x80 then v = v - 0x100 end
  return v
end

function Reader:u16()
  need(self, 2)
  local a, b = byte(self.s, self.p, self.p + 1)
  self.p = self.p + 2
  return a + b * 0x100
end

function Reader:i16()
  local v = self:u16()
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

function Reader:u32()
  need(self, 4)
  local a, b, c, d = byte(self.s, self.p, self.p + 3)
  self.p = self.p + 4
  return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

function Reader:i32()
  local v = self:u32()
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end

function Reader:f32()
  local b1, b2, b3, b4
  need(self, 4)
  b1, b2, b3, b4 = byte(self.s, self.p, self.p + 3)
  self.p = self.p + 4
  local sign = 1
  if b4 >= 0x80 then sign, b4 = -1, b4 - 0x80 end
  local expo = b4 * 2 + floor(b3 / 0x80)
  local mant = (b3 % 0x80) * 0x10000 + b2 * 0x100 + b1
  if expo == 0xFF then
    if mant == 0 then return sign * math.huge end
    return 0 / 0
  end
  if expo == 0 then return sign * mant * 2 ^ -149 end
  return sign * (1 + mant / 0x800000) * 2 ^ (expo - 127)
end

function Reader:fixed()
  return self:i32() / 65536
end

function Reader:raw(n)
  need(self, n)
  local out = self.s:sub(self.p, self.p + n - 1)
  self.p = self.p + n
  return out
end

local function newReader(bytes, limit)
  return setmetatable({ s = bytes, p = 5, limit = limit or #bytes }, Reader)
end

local function extensionStart(bytes)
  local n = #bytes
  if n < 12 or bytes:sub(n - 7, n - 4) ~= "S2HF" then return n + 1 end
  local p = n - 3
  local a, b, c, d = byte(bytes, p, p + 3)
  if not d then return n + 1 end
  local len = a + b * 0x100 + c * 0x10000 + d * 0x1000000
  local start = n - 7 - len
  if start < 5 then return n + 1 end
  return start
end

local function readComponent(r, frames, fixed)
  local array = r:u8() ~= 0
  local read = fixed and Reader.fixed or Reader.i16
  if not array then return read(r) end
  local out = {}
  for i = 1, frames do out[i] = read(r) end
  return out
end

local function readHeader(r, m, moveCount)
  m.species = r:u16()
  m.boneCount = r:u16()
  m.primCount = r:u16()
  m.texCount = r:u16()
  m.animCount = r:u16()
  m.auxCount = r:u16()
  m.rootScale = r:f32()
  m.staticPose = r:u8() ~= 0
  m.height = r:f32()
  m.floor = r:f32()
  m.radius = r:f32()
  m.moveAnim = {}
  m.moveAux = {}
  m.context = {}
  for i = 1, moveCount do m.moveAnim[i] = r:u16() end
  for i = 1, moveCount do m.moveAux[i] = r:i16() end
  for i = 1, #Pack.CONTEXTS do m.context[i] = r:u16() end
end

function Pack.validSpecies(species)
  species=tonumber(species)
  if not species or species<1 then return false end
  return species<=251 or species==Pack.SUBSTITUTE_SPECIES
    or (species>=Pack.UNOWN_FORM_FIRST and species<=Pack.UNOWN_FORM_LAST)
end

local function readBones(r, m)
  m.bones = {}
  for i = 1, m.boneCount do
    m.bones[i] = {
      parent = r:i16(),
      t = { r:i16(), r:i16(), r:i16() },
      r = { r:i16(), r:i16(), r:i16() },
      s = { r:fixed(), r:fixed(), r:fixed() },
    }
  end
end

local function readPrims(r, m)
  m.prims = {}
  for i = 1, m.primCount do
    local flags
    local prim = {
      tex = r:u16() + 1,
    }
    flags = r:u8()
    prim.cull = flags % 2 == 1
    prim.additive = math.floor(flags / 2) % 2 == 1
    prim.lighting = math.floor(flags / 4) % 2 == 1
    prim.callbackTextureRequired = math.floor(flags / 8) % 2 == 1
    prim.vertexSemantics = math.floor(flags / 16) % 2 == 1 and "color" or "normal"
    prim.sourceTextureMissing = math.floor(flags / 32) % 2 == 1
    prim.decal = math.floor(flags / 64) % 2 == 1
    prim.effect = math.floor(flags / 128) % 2 == 1 and "fire" or nil
    prim.geometryMode = r:u32()
    prim.sampler = { cms=r:u8(), cmt=r:u8(), masks=r:u8(), maskt=r:u8(),
      shifts=r:u8(), shiftt=r:u8() }
    -- S2IMP41 and older generated flame cards without func_810059D0's
    -- render-tile clamp state. Normalize them while reading so existing
    -- caches gain the ROM behaviour without a full model re-export.
    if prim.effect == "fire" then
      prim.sampler.cms, prim.sampler.cmt = 2, 2
      prim.sampler.masks, prim.sampler.maskt = 0, 0
      prim.sampler.shifts, prim.sampler.shiftt = 0, 0
    end
    prim.textureScale = { r:f32(), r:f32() }
    prim.texAnim = r:i16()
    local mapCount = r:u8()
    if mapCount > 0 then
      prim.texMap = {}
      for _ = 1, mapCount do prim.texMap[r:u8()] = r:u16() + 1 end
    end
    local fxCount = r:u16()
    if fxCount > 0 then
      prim.fxFrames = {}
      for k = 1, fxCount do prim.fxFrames[k] = r:u16() + 1 end
    end
    prim.nverts = r:u16()
    prim.nidx = r:u16()
    prim.pos, prim.uv, prim.nrm, prim.color, prim.skin = {}, {}, {}, {}, {}
    for k = 1, prim.nverts do
      prim.pos[k * 3 - 2] = r:i16()
      prim.pos[k * 3 - 1] = r:i16()
      prim.pos[k * 3] = r:i16()
      prim.uv[k * 2 - 1] = r:i16() / 512
      prim.uv[k * 2] = r:i16() / 512
      local a, b, c, alpha = r:u8(), r:u8(), r:u8(), r:u8()
      prim.color[k * 4 - 3], prim.color[k * 4 - 2] = a, b
      prim.color[k * 4 - 1], prim.color[k * 4] = c, alpha
      if a >= 128 then a = a - 256 end
      if b >= 128 then b = b - 256 end
      if c >= 128 then c = c - 256 end
      prim.nrm[k * 3 - 2], prim.nrm[k * 3 - 1], prim.nrm[k * 3] = a / 127, b / 127, c / 127
      prim.skin[k] = r:u8()
    end
    prim.idx = {}
    for k = 1, prim.nidx do prim.idx[k] = r:u16() + 1 end
    if prim.effect == "fire" and prim.nverts == 10 and prim.nidx == 24 then
      -- Older packs generated the same planar outline as regular row pairs,
      -- which changed the ROM's vertex order and interpolation diagonals.
      -- Upgrade it after consuming the stored payload so existing caches get
      -- the literal shared object without a DSM revision or re-export.
      local geometry = Flame.geometry(prim.skin[1] or 0)
      prim.pos, prim.uv, prim.nrm, prim.color, prim.skin = geometry.pos,
        geometry.uv, geometry.nrm, geometry.color, geometry.skin
      prim.nverts, prim.idx, prim.nidx = geometry.nverts, geometry.idx, geometry.nidx
      prim.vertexSemantics = "color"
    end
    m.prims[i] = prim
  end
end

local function readTextures(r, m)
  m.textures = {}
  for i = 1, m.texCount do
    local w, h, n = r:u16(), r:u16(), r:u32()
    if n ~= w * h * 4 then error("invalid DSM4 texture length", 0) end
    m.textures[i] = { w = w, h = h, rgba = r:raw(n) }
  end
end

local function normalizeFlameTextures(m)
  local slots = {}
  for _, prim in ipairs(m.prims or {}) do
    if prim.effect == "fire" and prim.nverts == 10 and prim.nidx == 24 then
      for _, slot in ipairs(prim.fxFrames or {}) do slots[slot] = true end
    end
  end
  for slot in pairs(slots) do
    local texture = m.textures and m.textures[slot]
    if texture and texture.w == 32 and texture.h == 32
        and type(texture.rgba) == "string" and #texture.rgba == 32*32*4 then
      -- Old caches expanded each source byte pair as one IA16 RGBA pixel.
      -- Recover those two bytes, then apply func_810059D0's actual IA8 render
      -- tile. This is lossless and avoids a ROM re-import/cache revision.
      local source = {}
      for p = 1, #texture.rgba, 4 do
        source[#source+1] = texture.rgba:sub(p,p)
        source[#source+1] = texture.rgba:sub(p+3,p+3)
      end
      local rgba = Palette.decodeNativeTexture(table.concat(source),32,64,3,1)
      if rgba then texture.w,texture.h,texture.rgba = 32,64,rgba end
    end
  end
end

local function readAnimations(r, m)
  m.anims = {}
  m.animByName = {}
  for i = 1, m.animCount do
    local nameLength = r:u8()
    local anim = {
      name = r:raw(nameLength),
      frames = r:u16(),
      loopStart = r:u16(),
      aux = r:i16(),
      tracks = {},
    }
    if anim.aux >= 0 then anim.aux = anim.aux + 1 else anim.aux = nil end
    for bi = 1, m.boneCount do
      if r:u8() ~= 0 then
        local tr = { t = {}, r = {}, s = {} }
        for c = 1, 3 do tr.t[c] = readComponent(r, anim.frames, false) end
        for c = 1, 3 do tr.r[c] = readComponent(r, anim.frames, false) end
        for c = 1, 3 do tr.s[c] = readComponent(r, anim.frames, true) end
        anim.tracks[bi] = tr
      end
    end
    anim.seconds = anim.frames / Pack.FPS
    m.anims[i] = anim
    if anim.name ~= "" and m.animByName[anim.name] == nil then m.animByName[anim.name] = i end
  end
end

local function readAux(r, m)
  m.auxAnims = {}
  for i = 1, m.auxCount do
    local a = { frames = r:u16(), loopStart = r:u16(), channels = {} }
    local channels = r:u16()
    for c = 1, channels do
      local n = r:u16()
      local stream = {}
      for k = 1, n do stream[k] = r:u16() end
      a.channels[c] = stream
    end
    m.auxAnims[i] = a
  end
end

local function attachMoveMetadata(m)
  for _, animation in ipairs(m.anims or {}) do animation.moveIds = {} end
  for moveId, animationIndex in ipairs(m.moveAnim or {}) do
    local animation = animationIndex ~= Pack.NONE
      and m.anims and m.anims[animationIndex + 1] or nil
    if animation then animation.moveIds[#animation.moveIds + 1] = moveId end
  end
end

-- The Pokédoll is a sparse special-purpose pose bank, not a Pokemon bank.
-- Its only exported motion is the 94-frame reaction; ROM selector zero means
-- the model's bind pose, while selector three selects that reaction. Older
-- S2IMP53 packs compacted the bank to one clip and mislabeled it as idle.
-- Repair at load time as well as for new imports, without requiring another
-- ROM import or changing any ordinary species' animation routing.
local function restoreSubstituteIdle(m)
  if m.species~=Pack.SUBSTITUTE_SPECIES or #m.anims~=1
      or m.context[1]~=0 or m.context[4]~=2 then return end
  local hit=m.anims[1]
  hit.name="hit"
  m.anims[2]={name="idle",frames=1,loopStart=0,tracks={},aux=-1}
  m.animCount=2
  m.animByName={hit=1,idle=2}
  for i,selector in ipairs(m.context) do
    if selector==0 then m.context[i]=1
    elseif selector==2 then m.context[i]=0 end
  end
  for i,selector in ipairs(m.moveAnim) do
    if selector==0 then m.moveAnim[i]=1
    elseif selector==2 then m.moveAnim[i]=0 end
  end
  m.staticPose=false
end

function Pack.parse(bytes)
  local magic = type(bytes) == "string" and bytes:sub(1, 4) or nil
  if magic ~= "DSM4" and magic ~= "DSM5" then return nil, "not a DSM pack" end
  local baseEnd = extensionStart(bytes) - 1
  local ok, result = pcall(function()
    local r = newReader(bytes, baseEnd)
    local m = { bytes = bytes }
    m.packVersion = magic
    readHeader(r, m, magic == "DSM5" and Pack.N_MOVES or Pack.LEGACY_N_MOVES)
    if not Pack.validSpecies(m.species) then
      error("invalid DSM4 species", 0)
    end
    if m.boneCount > 1024 or m.primCount > 4096 or m.texCount > 4096 or m.animCount > 4096 then
      error("invalid DSM4 counts", 0)
    end
    readBones(r, m)
    readPrims(r, m)
    readTextures(r, m)
    normalizeFlameTextures(m)
    readAnimations(r, m)
    readAux(r, m)
    restoreSubstituteIdle(m)
    attachMoveMetadata(m)
    if r.p - 1 ~= baseEnd then error("unexpected DSM4 base payload length", 0) end
    m.handlers = Handlers.readExtension(bytes)
    Materials.attach(m)
    local textureReport = TextureParity.audit(m, { indexBase = 1 })
    if #textureReport.issues > 0 then
      error("invalid DSM4 texture contract: " .. textureReport.issues[1].message, 0)
    end
    m.textureMetrics = textureReport.metrics
    return m
  end)
  if not ok then return nil, tostring(result) end
  return result
end

function Pack.contextSelector(model, name)
  if type(model) ~= "table" or type(name) ~= "string" then return nil end
  for i, context in ipairs(Pack.CONTEXTS) do
    if context == name then
      local index = model.context and model.context[i]
      if index and index ~= Pack.NONE then return index end
      return nil
    end
  end
  return nil
end

function Pack.contextIndex(model, name)
  local selector = Pack.contextSelector(model, name)
  if selector and selector < #(model.anims or {}) then return selector + 1 end
  return nil
end

function Pack.moveSelector(model, move)
  move = tonumber(move)
  if not (model and move and move >= 1 and move <= Pack.N_MOVES) then return nil end
  local index = model.moveAnim and model.moveAnim[move]
  if index and index ~= Pack.NONE then return index end
  return nil
end

function Pack.moveIndex(model, move)
  local selector = Pack.moveSelector(model, move)
  if selector and selector < #(model.anims or {}) then return selector + 1 end
  return nil
end

function Pack.textureIndex(model, prim, animIndex, frame, auxIndex, effectFrame)
  if not (model and prim) then return nil end
  local index = prim.tex
  if prim.fxFrames and #prim.fxFrames>0 then
    local at=math.floor(tonumber(effectFrame) or 0)%#prim.fxFrames+1
    return prim.fxFrames[at]
  end
  local anim = animIndex and model.anims and model.anims[animIndex] or nil
  local auxSlot=auxIndex or (anim and anim.aux)
  local aux = auxSlot and model.auxAnims and model.auxAnims[auxSlot] or nil
  if aux and prim.texAnim and prim.texAnim >= 0 and prim.texMap then
    local stream = aux.channels[prim.texAnim + 1]
    if stream and #stream > 0 then
      local at = math.floor(tonumber(frame) or 0) + 1
      if at < 1 then at = 1 end
      if at > #stream then at = #stream end
      local mapped = prim.texMap[stream[at]]
      if mapped then index = mapped end
    end
  end
  return index
end

function Pack.image(model, index)
  local slot = model and model.textures and model.textures[index]
  if not slot then return nil end
  if slot.image ~= nil then return slot.image or nil end
  if not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then return nil end
  local ok, image = pcall(function()
    local data = love.image.newImageData(slot.w, slot.h, "rgba8", slot.rgba)
    local wantsMipmaps = model.staticPose == true and tonumber(model.species) == 0
    local made, out = pcall(love.graphics.newImage, data,
      wantsMipmaps and { mipmaps = true } or nil)
    if not made then out = love.graphics.newImage(data) end
    if out.setFilter then
      out:setFilter(wantsMipmaps and "linear" or "nearest",
        wantsMipmaps and "linear" or "nearest", wantsMipmaps and 16 or 1)
    end
    if wantsMipmaps and out.setMipmapFilter then
      pcall(out.setMipmapFilter, out, "linear", 0)
    end
    if out.setWrap then pcall(out.setWrap, out, "clamp", "clamp") end
    return out
  end)
  slot.image = ok and image or false
  return slot.image or nil
end

function Pack.release(model)
  if not (model and model.textures) then return end
  for _, slot in ipairs(model.textures) do
    if slot.image and slot.image.release then pcall(slot.image.release, slot.image) end
    slot.image = nil
  end
end

return Pack
