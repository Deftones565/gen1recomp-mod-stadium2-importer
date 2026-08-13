
local StadiumFragment = {}
local Fx = require("mods.STADIUM2_IMPORTER.lib.fx")
local Phase5Geometry = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")
local HandlerRegistry = require("mods.STADIUM2_IMPORTER.lib.handler_registry")
local VertexSemantics = require("mods.STADIUM2_IMPORTER.lib.vertex_semantics")

local byte = string.byte
local char = string.char
local sub = string.sub
local concat = table.concat
local floor = math.floor

local BASE = 0x8FF00000

function StadiumFragment.setBase(value)
  BASE = assert(tonumber(value), "fragment base must be numeric")
end

local CMD_SIZES = {
  [0x00] = 0x08, [0x01] = 0x04, [0x02] = 0x08, [0x03] = 0x08, [0x04] = 0x04,
  [0x05] = 0x04, [0x06] = 0x04, [0x07] = 0x08, [0x08] = 0x0C, [0x09] = 0x04,
  [0x0A] = 0x08, [0x0B] = 0x18, [0x0C] = 0x04, [0x0D] = 0x04, [0x0E] = 0x04,
  [0x0F] = 0x04, [0x10] = 0x04, [0x11] = 0x04, [0x12] = 0x04, [0x13] = 0x08,
  [0x14] = 0x0C, [0x15] = 0x0C, [0x16] = 0x04, [0x17] = 0x14, [0x18] = 0x08,
  [0x19] = 0x08, [0x1A] = 0x04, [0x1B] = 0x10, [0x1C] = 0x10, [0x1D] = 0x1C,
  [0x1E] = 0x08, [0x1F] = 0x18, [0x20] = 0x14, [0x21] = 0x10, [0x22] = 0x08,
  [0x23] = 0x10, [0x24] = 0x04, [0x25] = 0x04, [0x26] = 0x14,
  [0x28] = 0x04, [0x29] = 0x04,
}

StadiumFragment.CMD_SIZES = CMD_SIZES


local function roundHalfEven(x)
  local f = floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 end
  if d < 0.5 then return f end
  if f % 2 == 0 then return f end
  return f + 1
end

local function roundTo(x, nd)
  if nd == 0 then return roundHalfEven(x) end
  if x ~= x or x == math.huge or x == -math.huge then return x end
  local s = string.format("%." .. (nd + 24) .. "f", x)
  local dot = s:find(".", 1, true)
  local tail = s:sub(dot + nd + 1)
  if not tail:match("^50*$") then
    return tonumber(string.format("%." .. nd .. "f", x))
  end
  local head = s:sub(1, dot + nd)         
  local last = head:byte(-1) - 48
  if last % 2 == 0 then return tonumber(head) end
  return tonumber(head:sub(1, -2) .. string.char(head:byte(-1) + 1))
end

StadiumFragment.roundHalfEven = roundHalfEven
StadiumFragment.roundTo = roundTo

local function signed(v, bits)
  local m = 2 ^ (bits - 1)
  if v >= m then return v - m * 2 end
  return v
end

StadiumFragment.signed = signed

local function unique(seq, n)
  local seen, out, m = {}, {}, 0
  for i = 1, n or #seq do
    local v = seq[i]
    if v ~= nil and not seen[v] then
      seen[v] = true
      m = m + 1
      out[m] = v
    end
  end
  return out, m
end


local Frag = {}
Frag.__index = Frag

function Frag:u8(o)
  return byte(self.d, o + 1)
end

function Frag:s8(o)
  local v = byte(self.d, o + 1)
  if v >= 128 then return v - 256 end
  return v
end

function Frag:u16(o)
  local a, b = byte(self.d, o + 1, o + 2)
  return a * 256 + b
end

function Frag:s16(o)
  local a, b = byte(self.d, o + 1, o + 2)
  local v = a * 256 + b
  if v >= 32768 then return v - 65536 end
  return v
end

function Frag:u32(o)
  local a, b, c, d = byte(self.d, o + 1, o + 4)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

function Frag:s32(o)
  local v = self:u32(o)
  if v >= 2147483648 then return v - 4294967296 end
  return v
end

function Frag:off(ptr)
  if ptr == 0 then return nil end
  return ptr - BASE
end

function Frag:ptr(o)
  return self:off(self:u32(o))
end

function Frag:root()
  for o = 0x20, 0x7C, 4 do
    local w = self:u32(o)
    if floor(w / 0x4000000) == 0x0F then              
      local reg = floor(w / 0x10000) % 0x20
      local w2 = self:u32(o + 4)
      if floor(w2 / 0x4000000) == 0x09                
          and floor(w2 / 0x200000) % 0x20 == reg then
        return self:u16(o + 2) * 65536 + self:s16(o + 6) - BASE
      end
    end
  end
  return nil
end

function Frag:ptrList(o)
  local out, n = {}, 0
  while true do
    local p = self:ptr(o)
    if p == nil then return out, n end
    n = n + 1
    out[n] = p
    o = o + 4
  end
end

function StadiumFragment.open(data, name)
  if type(data) ~= "string" or #data < 0x20 then
    return nil, (name or "?") .. ": too short to be a module"
  end
  if sub(data, 9, 16) ~= "FRAGMENT" then
    return nil, (name or "?") .. ": not a FRAGMENT module"
  end
  return setmetatable({ d = data, name = name or "<bytes>" }, Frag)
end


local Model = {}
Model.__index = Model

local function newModel(frag, options)
  local r = frag:root()
  if not r then return nil, frag.name .. ": could not locate root struct" end
  local geo = frag:ptr(r + 0x08)
  local anims = frag:ptr(r + 0x0C)
  local aux = frag:ptr(r + 0x10)
  local m = setmetatable({
    f = frag,
    species = frag:u16(r),
    geoLayouts = geo and frag:ptrList(geo) or {},
    anims = anims and frag:ptrList(anims) or {},
    auxAnims = aux and frag:ptrList(aux) or {},
    textures = {},          
    tluts = {},             
    bones = {},             
    boneById = {},
    prims = {},             
    primsByKey = {},
    rootScale = { 1.0, 1.0, 1.0 },
    fx = {},                
    warnings = {},
    options = type(options) == "table" and options or {},
  }, Model)
  return m
end

function Model:readTextureTable(off, count)
  local f = self.f
  local t = self.textures
  for i = 0, count - 1 do
    local o = off + i * 0xC
    t[#t + 1] = {
      fmt = f:u8(o), siz = f:u8(o + 1), w = f:s16(o + 2),
      h = f:u16(o + 4), texels = f:u16(o + 6), data = f:ptr(o + 8),
    }
  end
end

function Model:readTlutTable(off, count)
  local f = self.f
  for i = 0, count - 1 do
    local o = off + i * 0xC
    local rec = { count = f:u16(o + 2), data = f:ptr(o + 4), dl = f:ptr(o + 8) }
    local dl = rec.dl
    if dl ~= nil then
      for _ = 1, 16 do
        local w0, w1 = f:u32(dl), f:u32(dl + 4)
        local op = floor(w0 / 0x1000000)
        if op == 0xFD then                            
          rec.data = f:off(w1)
        elseif op == 0xF0 then                        
          rec.count = floor(w1 / 0x4000) % 0x400 + 1
        elseif op == 0xDF then
          break
        end
        dl = dl + 8
      end
    end
    self.tluts[#self.tluts + 1] = rec
  end
end

function Model:curBone()
  local n = #self.stack
  if n >= 2 then return self.stack[n - 1] end
  return -1
end

function Model:build()
  self.curTex = -1
  self.curTlut = -1
  self.curMat = nil
  self.curTexAnim = -1
  self.stack = { -1 }
  self.vbuf = {}
  if not self.geoLayouts[1] then
    self.warnings[#self.warnings + 1] = "no geo layout"
    return
  end
  self:walk(self.geoLayouts[1], 0)
end

function Model:walk(o, depth)
  local f = self.f
  if depth > 32 or o == nil then return end
  while true do
    local cmd = f:u8(o)
    local size = CMD_SIZES[cmd]
    if size == nil then
      self.warnings[#self.warnings + 1] =
        ("unknown geo cmd 0x%02x at 0x%x"):format(cmd or -1, o)
      return
    end
    if cmd == 0x01 or cmd == 0x04 then                
      return
    elseif cmd == 0x00 or cmd == 0x03 then            
      self:walk(f:ptr(o + 4), depth + 1)
    elseif cmd == 0x02 then                           
      o = f:ptr(o + 4)
      if o == nil then return end
      cmd = nil                                       
    elseif cmd == 0x05 then                           
      local n = #self.stack
      self.stack[n + 1] = self.stack[n]
    elseif cmd == 0x06 then                           
      self.stack[#self.stack] = nil
    elseif cmd == 0x17 then                           
      self:readTextureTable(f:ptr(o + 8), f:s16(o + 2))
      if f:ptr(o + 0xC) then
        self:readTlutTable(f:ptr(o + 0xC), f:s16(o + 4))
      end
      self.vtxBase = f:ptr(o + 0x10)
      self.nVerts = f:s16(o + 6)
    elseif cmd == 0x08 then                           
      local handler = f:u32(o + 4)
      local bone = self:curBone()
      local arg = f:ptr(o + 8)
      -- Stadium's node order is draw first, callback second. Bind the
      -- callback to the exact primitive set emitted by the preceding draw
      -- command; grouping only by texture/material merged unrelated nodes
      -- and left every material callback with no consumer.
      -- Most callbacks decorate the draw immediately before the command.
      -- 0x81000140 is the exception: func_810024E0 installs phase-5 state for
      -- the geometry that follows it. Retrospectively claiming the previous
      -- draw merges neighbouring meshes and makes one callback site orphaned.
      local contract = HandlerRegistry.info(handler)
      if not contract or contract.ownership == "preceding" then
        local owned = self.lastDrawPrimsByBone and self.lastDrawPrimsByBone[bone]
        for _, prim in ipairs(owned or {}) do
          prim.callbackOffset = o
          prim.callbackDescriptor = handler
        end
      end
      self.callbackForBone = self.callbackForBone or {}
      self.callbackForBone[bone] = { offset = o, descriptor = handler }
      self.fx[#self.fx + 1] = {
        bone = bone,
        boneId = self.bones[bone + 1] and self.bones[bone + 1].boneId or nil,
        handler = handler,
        callback = handler,
        arg = arg,
        argOffset = arg,
        argPointer = arg and (BASE + arg) or 0,
        commandOffset = o,
      }
    elseif cmd == 0x1C then                           
      self.rootScale = { f:s32(o + 4) / 65536.0, f:s32(o + 8) / 65536.0,
                         f:s32(o + 0xC) / 65536.0 }
    elseif cmd == 0x1D then                           
      local idx = #self.bones                         
      self.bones[idx + 1] = {
        parent = self:curBone(), boneId = f:u8(o + 1), flags = f:u8(o + 2),
        chan = f:s8(o + 3),
        t = { f:s16(o + 4), f:s16(o + 6), f:s16(o + 8) },
        r = { f:s16(o + 0xA), f:s16(o + 0xC), f:s16(o + 0xE) },
        s = { f:s32(o + 0x10) / 65536.0, f:s32(o + 0x14) / 65536.0,
              f:s32(o + 0x18) / 65536.0 },
      }
      self.boneById[f:u8(o + 1)] = idx
      self.stack[#self.stack] = idx
    elseif cmd == 0x23 then                           
      self.curTex = f:s16(o + 8)
      self.curTlut = f:s16(o + 0xA)
      self.curMat = f:ptr(o + 4)
      self.curTexAnim = f:s16(o + 2)
    elseif cmd == 0x22 then                           
      self:runNodeDL(f:ptr(o + 4), self:curBone())
    elseif cmd == 0x1E then                           
      local named = self.boneById[f:s16(o + 2)]
      self:runNodeDL(f:ptr(o + 4), named or self:curBone())
    elseif cmd == 0x20 or cmd == 0x21 then            
      self:runNodeDL(f:ptr(o + (cmd == 0x20 and 0x10 or 0xC)), self:curBone())
    end
    if cmd ~= nil then o = o + size end
  end
end

function Model:nodeCallback(bone)
  local callbacks = self.callbackForBone
  while callbacks and bone and bone >= 0 do
    if callbacks[bone] then return callbacks[bone] end
    local row = self.bones[bone + 1]
    bone = row and row.parent or -1
  end
  return nil
end

function Model:runNodeDL(offset, bone)
  local oldOffset, oldDescriptor = self.curCallbackOffset, self.curCallbackDescriptor
  local callback = self:nodeCallback(bone)
  if callback then
    self.curCallbackOffset = callback.offset
    self.curCallbackDescriptor = callback.descriptor
  end
  self:runDL(offset, bone, 0)
  self.curCallbackOffset, self.curCallbackDescriptor = oldOffset, oldDescriptor
end

function Model:primFor(tex, tlut, mat, texAnim, cull)
  local key = tex .. "," .. tlut .. "," .. tostring(mat) .. ","
              .. texAnim .. "," .. cull .. "," .. tostring(self.curCallbackOffset)
              .. "," .. tostring(self.drawSerial)
  local p = self.primsByKey[key]
  if p == nil then
    p = { tex = tex, tlut = tlut, mat = mat, texAnim = texAnim, cull = cull,
          callbackOffset = self.curCallbackOffset,
          callbackDescriptor = self.curCallbackDescriptor,
          verts = {}, nverts = 0, tris = {}, ntris = 0, remap = {} }
    self.primsByKey[key] = p
    self.prims[#self.prims + 1] = p
  end
  if self.currentDrawPrims and not p.currentDrawMark then
    p.currentDrawMark = self.drawSerial
    self.currentDrawPrims[#self.currentDrawPrims + 1] = p
  end
  return p
end

local function band(a, b, bits)
  local r, p = 0, 1
  for _ = 1, bits do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = floor(a / 2), floor(b / 2), p * 2
  end
  return r
end

local function bor(a, b, bits)
  local r, p = 0, 1
  for _ = 1, bits do
    if a % 2 == 1 or b % 2 == 1 then r = r + p end
    a, b, p = floor(a / 2), floor(b / 2), p * 2
  end
  return r
end

local function emit(prim, vbuf, flip, ia, ib, ic)
  local remap, verts = prim.remap, prim.verts
  local tri = { 0, 0, 0 }
  for k = 1, 3 do
    local v = vbuf[k == 1 and ia or (k == 2 and ib or ic)]
    if v == nil then return end
    local key = v[1] .. "," .. v[2] .. "," .. v[3] .. "," .. v[4] .. ","
                .. v[5] .. "," .. v[6] .. "," .. v[7] .. "," .. v[8]
                .. "," .. v[9] .. "," .. v[10]
    local j = remap[key]
    if j == nil then
      j = prim.nverts                                 
      remap[key] = j
      prim.nverts = j + 1
      verts[j + 1] = v
    end
    tri[k] = j
  end
  if flip then tri[1], tri[3] = tri[3], tri[1] end
  prim.ntris = prim.ntris + 1
  prim.tris[prim.ntris] = tri
end

function Model:runDL(o, bone, depth)
  if o == nil or depth > 8 or o < 0 or o + 8 > #self.f.d then return end
  if depth == 0 then
    self.drawSerial = (self.drawSerial or 0) + 1
    self.currentDrawPrims = {}
    self.lastDrawPrimsByBone = self.lastDrawPrimsByBone or {}
    -- Store the table by reference now; recursive display lists populate it.
    self.lastDrawPrimsByBone[bone] = self.currentDrawPrims
  end
  local f = self.f
  local vbuf = self.vbuf
  -- The model dispatcher enters these child lists with lighting and back-face
  -- culling enabled.  Their usual D9FFFFFF/00000400 command preserves that
  -- inherited lighting bit; starting from culling alone loses caller state.
  local geometryMode = 0x20400
  local steps = 0
  while o >= 0 and o + 8 <= #f.d and steps < 4096 do
    steps = steps + 1
    local w0, w1 = f:u32(o), f:u32(o + 4)
    local op = floor(w0 / 0x1000000)
    o = o + 8
    if op == 0xDF then                                
      return
    elseif op == 0xDE then                            
      self:runDL(f:off(w1), bone, depth + 1)
      if floor(w0 / 0x10000) % 256 ~= 0 then          
        return
      end
    elseif op == 0x01 then                            
      local n = floor(w0 / 0x1000) % 256
      local v0 = floor((w0 % 0x1000) / 2) - n
      local a = f:off(w1)
      if a then
        for i = 0, n - 1 do
          local p = a + i * 0x10
          local slot = v0 + i
          if slot >= 0 and slot < 64 then
            vbuf[slot] = { f:s16(p), f:s16(p + 2), f:s16(p + 4),
                           f:s16(p + 8), f:s16(p + 10),
                           f:s8(p + 12), f:s8(p + 13), f:s8(p + 14),
                           f:u8(p + 15), bone }
          end
        end
      end
    elseif op == 0xD9 then                            
      -- F3DEX2 stores a 24-bit keep mask in w0 and the bits to set in w1.
      -- Preserve the full state, including inherited G_LIGHTING; culling is
      -- only one part of the geometry-mode contract.
      geometryMode = bor(band(geometryMode, w0 % 0x1000000, 24),
        w1 % 0x1000000, 24)
    elseif op == 0x05 or op == 0x06 then              
      local prim = self:primFor(self.curTex, self.curTlut, self.curMat,
                                self.curTexAnim, geometryMode)
      local flip = (floor(geometryMode / 0x200) % 2 == 1)
                   and (floor(geometryMode / 0x400) % 2 == 0)
      emit(prim, vbuf, flip,
           floor(floor(w0 / 0x10000) % 256 / 2),
           floor(floor(w0 / 0x100) % 256 / 2),
           floor(w0 % 256 / 2))
      if op == 0x06 then
        emit(prim, vbuf, flip,
             floor(floor(w1 / 0x10000) % 256 / 2),
             floor(floor(w1 / 0x100) % 256 / 2),
             floor(w1 % 256 / 2))
      end
    end
  end
end

function Model:tilePalette(mat)
  if mat == nil then return 0 end
  local f = self.f
  local pal = 0
  for _ = 1, 16 do
    local w0, w1 = f:u32(mat), f:u32(mat + 4)
    local op = floor(w0 / 0x1000000)
    if op == 0xF5 and floor(w1 / 0x1000000) % 8 == 0 then   
      pal = floor(w1 / 0x100000) % 16
    elseif op == 0xDF then
      break
    end
    mat = mat + 8
  end
  return pal
end

function Model:bakePhase5Geometry()
  local f = self.f
  local seen = {}
  for _, node in ipairs(self.fx) do
    if (node.handler == 0x81000140 or node.handler == 0x81000030
        or node.handler == 0x81000040 or node.handler == 0x81000070) and node.arg then
      local item = node.handler == 0x81000140 and f:ptr(node.arg) or nil
      local staticPhase5 = item and f:u32(item + 4) == 0
      -- The static 0x140 path only changes render state. Its argument is not
      -- a display-list table; scanning 0x400 bytes crosses into adjacent data
      -- and manufactured hundreds of triangles for Misdreavus and its peers.
      if node.handler == 0x81000140 then
        -- func_810024E0 only emits render-state commands before delegating
        -- texture loading to func_81001F14. item[4] controls dynamic state;
        -- it is not a geometry pointer or display-list table.
        node.phase5Geometry = "state-only"
        node.phase5DynamicState = not staticPhase5
      else
        local scanLength = 0x100
        local material
        for at = node.arg, math.min(#f.d - 4, node.arg + scanLength), 4 do
          local pointer = f:u32(at)
          local offset = f:off(pointer)
          if offset then
            local op = f:u8(offset)
            if not material and (op == 0xF5 or op == 0xFA or op == 0xFB
                or op == 0xFC or op == 0xFD) then
              material = offset
            end
          end
        end
        local oldMat, oldCallback, oldDescriptor = self.curMat, self.curCallbackOffset,
          self.curCallbackDescriptor
        self.curCallbackOffset = node.commandOffset
        self.curCallbackDescriptor = node.handler
        if material then self.curMat = material end
        for at = node.arg, math.min(#f.d - 4, node.arg + scanLength), 4 do
          local pointer = f:u32(at)
          local offset = f:off(pointer)
          local op = offset and f:u8(offset) or nil
          local key = tostring(offset) .. ":" .. tostring(node.bone)
          if offset and not seen[key]
              and (op == 0x01 or op == 0x05 or op == 0x06 or op == 0xDE) then
            seen[key] = true
            self:runDL(offset, node.bone, 0)
          end
        end
        self.curMat = oldMat
        self.curCallbackOffset = oldCallback
        self.curCallbackDescriptor = oldDescriptor
      end
    end
  end
end

function Model:mergePrimitivesByCallback()
  local merged, byKey = {}, {}
  for _, source in ipairs(self.prims) do
    local key = table.concat({ source.tex, source.tlut, tostring(source.mat),
      source.texAnim, source.cull, tostring(source.callbackOffset),
      tostring(source.callbackDescriptor) }, ",")
    local target = byKey[key]
    if not target then
      target = source
      byKey[key] = target
      merged[#merged + 1] = target
    elseif source.ntris > 0 then
      local base = target.nverts
      for _, vertex in ipairs(source.verts) do
        target.nverts = target.nverts + 1
        target.verts[target.nverts] = vertex
      end
      for _, tri in ipairs(source.tris) do
        target.ntris = target.ntris + 1
        target.tris[target.ntris] = { tri[1] + base, tri[2] + base, tri[3] + base }
      end
    end
  end
  self.prims = merged
end


local function bitfield(f, base, index, bits)
  local bitpos = index * bits
  local word
  if bitpos >= 0 then
    word = floor(bitpos / 16)
  else
    word = -floor(-bitpos / 16)
  end
  local rem = bitpos - word * 16
  local o = base + word * 2
  local v = f:u16(o) * 65536 + f:u16(o + 2)
  local shift = rem % 32
  local keep = 2 ^ (32 - shift)
  v = (v % keep) * 2 ^ shift
  return signed(floor(v / 2 ^ (32 - bits)), bits)
end

StadiumFragment.bitfield = bitfield

local Anim = {}
Anim.__index = Anim

local function newAnim(frag, off)
  return setmetatable({
    f = frag, off = off,
    flags      = frag:u16(off),
    startFrame = frag:u16(off + 4),
    loopStart  = frag:u16(off + 6),
    nChannels  = frag:u16(off + 8),
    nFrames    = frag:u16(off + 0xA),
    chanTable  = frag:ptr(off + 0xC),
    scaleData  = frag:ptr(off + 0x10),
    rotData    = frag:ptr(off + 0x14),
    transData  = frag:ptr(off + 0x18),
  }, Anim)
end

function Anim:chan(i)
  local o = self.chanTable + i * 0xA
  local f = self.f
  return { nScale = f:u8(o), nRot = f:u8(o + 1), nTrans = f:u8(o + 2),
           interp = f:u8(o + 3), oScale = f:u16(o + 4),
           oRot = f:u16(o + 6), oTrans = f:u16(o + 8) }
end

function Anim:transPacked(c, frame)
  if c.nTrans == 0 then return nil end
  local wide = floor(self.flags / 4) % 2 == 1
  local bits = wide and 16 or 12
  if c.nTrans == 1 then
    if wide then return signed(c.oTrans, 16) + 0.0 end
    return floor(signed(c.oTrans * 16 % 65536, 16) / 16) + 0.0
  end
  local i = c.oTrans + (frame < c.nTrans - 1 and frame or c.nTrans - 1)
  return bitfield(self.f, self.transData, i, bits) + 0.0
end

function Anim:rotPacked(c, frame)
  if c.nRot == 0 then return nil end
  if c.nRot == 1 then return signed(c.oRot * 16 % 65536, 16) end
  local i = c.oRot + (frame < c.nRot - 1 and frame or c.nRot - 1)
  return signed(bitfield(self.f, self.rotData, i, 12) * 16 % 65536, 16)
end

function Anim:scalePacked(c, frame)
  if c.nScale == 0 then return nil end
  if c.nScale == 1 then return c.oScale / 1000.0 end
  local i = c.oScale + (frame < c.nScale - 1 and frame or c.nScale - 1)
  return self.f:s16(self.scaleData + i * 2) / 1000.0
end

function Anim:hermite(base, n, frame, wide)
  local f = self.f
  local stride = wide and 8 or 6
  local function key(i)
    local o = base + i * stride
    return f:s16(o), f:s16(o + 2), f:s16(o + 4),
           wide and f:s16(o + 6) or f:s16(o + 4)
  end
  local k0t, k0v = key(0)
  if k0t >= frame then return k0v + 0.0 end
  local lt, lv = key(n - 1)
  if frame >= lt then return lv + 0.0 end
  local i = 0
  while i < n - 2 do
    if frame < (key(i + 1)) then break end
    i = i + 1
  end
  local at, av, ao, aw = key(i)
  local bt, bv, bo = key(i + 1)
  local x = (frame - at) / 30.0
  local y = 30.0 / (bt - at)
  local x2, x3 = x * x, x * x * x
  local y2, y3 = y * y, y * y * y
  return av * (2 * x3 * y3 - 3 * x2 * y2 + 1)
         + bv * (-2 * x3 * y3 + 3 * x2 * y2)
         + (wide and aw or ao) * (x3 * y2 - 2 * x2 * y + x)
         + bo * (x3 * y2 - x2 * y)
end

function Anim:transKey(c, frame)
  if c.nTrans < 2 then return signed(c.oTrans, 16) + 0.0 end
  return self:hermite(self.transData + c.oTrans * 2, c.nTrans, frame,
                      c.interp % 2 == 1)
end

function Anim:rotKey(c, frame)
  local deg
  if c.nRot < 2 then
    deg = signed(c.oRot, 16) / 10.0
  else
    deg = self:hermite(self.rotData + c.oRot * 2, c.nRot, frame,
                       floor(c.interp / 2) % 2 == 1) / 10.0
  end
  deg = deg % 360.0
  return signed(floor(deg / 360.0 * 65536.0) % 65536, 16)
end

function Anim:scaleKey(c, frame)
  if c.nScale < 2 then return signed(c.oScale, 16) / 100.0 end
  return self:hermite(self.scaleData + c.oScale * 2, c.nScale, frame,
                      floor(c.interp / 4) % 2 == 1) / 100.0
end

-- The animation player's frame counter is already in the channel streams' own
-- coordinate system.  The header word at +4 is the counter's INITIAL value;
-- it is not an offset added by the samplers.  The game initializes the counter
-- from +4, then the packed/Hermite routines index their streams with that
-- counter directly.  Likewise +6 is the loop target and +0xA is the end.
--
-- Keep extraction frame-for-frame with the source streams.  Adding startFrame
-- here (the previous shifted-counter behavior) double-applies the initial counter and makes later
-- bones clamp to unrelated tail values.
function Anim:sampleTrs(chanIndex, frame, bt, br, bs)
  frame = tonumber(frame) or 0
  local base = chanIndex * 3
  if base < 0 or base + 2 >= self.nChannels then return nil end
  local c1, c2, c3 = self:chan(base), self:chan(base + 1), self:chan(base + 2)
  local t, r, s = {}, {}, {}
  if floor(self.flags / 8) % 2 == 1 then
    t[1], t[2], t[3] = self:transKey(c1, frame), self:transKey(c2, frame),
                       self:transKey(c3, frame)
    r[1], r[2], r[3] = self:rotKey(c1, frame), self:rotKey(c2, frame),
                       self:rotKey(c3, frame)
    s[1], s[2], s[3] = self:scaleKey(c1, frame), self:scaleKey(c2, frame),
                       self:scaleKey(c3, frame)
  else
    t[1], t[2], t[3] = self:transPacked(c1, frame), self:transPacked(c2, frame),
                       self:transPacked(c3, frame)
    r[1], r[2], r[3] = self:rotPacked(c1, frame), self:rotPacked(c2, frame),
                       self:rotPacked(c3, frame)
    s[1], s[2], s[3] = self:scalePacked(c1, frame),
                       self:scalePacked(c2, frame), self:scalePacked(c3, frame)
  end
  for k = 1, 3 do
    if t[k] == nil then t[k] = bt[k] end
    if r[k] == nil then r[k] = br[k] end
    if s[k] == nil then s[k] = bs[k] end
  end
  return t, r, s
end

local Aux = {}
Aux.__index = Aux

local function newAux(frag, off)
  return setmetatable({
    f = frag,
    flags      = frag:u16(off),   

    startFrame = frag:u16(off + 4),
    loopStart  = frag:u16(off + 6),
    nChannels  = frag:u16(off + 8),
    nFrames    = frag:u16(off + 0xA),
    chanTable  = frag:ptr(off + 0xC),
    data       = frag:ptr(off + 0x10),
  }, Aux)
end

function Aux:sample(chan, frame)
  if chan < 0 or chan >= self.nChannels or self.chanTable == nil then
    return nil
  end
  -- Same counter semantics as skeletal animation: the caller supplies the
  -- actual stream frame.  startFrame initializes playback; it is not added by
  -- the texture sampler.
  frame = tonumber(frame) or 0
  local o = self.chanTable + chan * 4
  local count, base = self.f:u16(o), self.f:u16(o + 2)
  if count == 0 then return nil end
  local i = base + (frame < count and frame or count - 1)
  return self.f:u8(self.data + i)
end

function Aux:track(chan)
  local n = self.nFrames > 1 and self.nFrames or 1
  local out = {}
  for i = 0, n - 1 do out[i + 1] = self:sample(chan, i) end
  return out, n
end


local function rgba5551(p)
  return floor(floor(p / 2048) % 32 * 255 / 31),
         floor(floor(p / 64) % 32 * 255 / 31),
         floor(floor(p / 2) % 32 * 255 / 31),
         (p % 2 == 1) and 255 or 0
end

local function decodeTexture(f, tex, tlut, palette)
  local w, h, fmt, siz, addr = tex.w, tex.h, tex.fmt, tex.siz, tex.data
  local n = w * h
  if n <= 0 or addr == nil then
    return w, h, string.rep("\255\0\255\255", n > 0 and n or 0)
  end
  local d = f.d
  local out = {}

  local function nibble(i)
    local v = byte(d, addr + floor(i / 2) + 1)
    if i % 2 == 1 then return v % 16 end
    return floor(v / 16)
  end

  if fmt == 0 and siz == 2 then                       
    for i = 0, n - 1 do
      local a, b = byte(d, addr + i * 2 + 1, addr + i * 2 + 2)
      out[i + 1] = char(rgba5551(a * 256 + b))
    end
  elseif fmt == 0 and siz == 3 then                   
    return w, h, sub(d, addr + 1, addr + n * 4)
  elseif fmt == 2 then                                
    local pal, np = {}, 0
    if tlut ~= nil and tlut.data ~= nil then
      local base = tlut.data + (siz == 0 and palette * 16 * 2 or 0)
      np = (siz == 0) and 16 or 256
      for i = 0, np - 1 do
        local a, b = byte(d, base + i * 2 + 1, base + i * 2 + 2)
        pal[i + 1] = char(rgba5551(a * 256 + b))
      end
    end
    if np == 0 then
      np = 256
      for i = 1, np do pal[i] = "\255\0\255\255" end
    end
    for i = 0, n - 1 do
      local idx = (siz == 0) and nibble(i) or byte(d, addr + i + 1)
      out[i + 1] = pal[idx % np + 1]
    end
  elseif fmt == 3 then                                
    for i = 0, n - 1 do
      local l, a
      if siz == 2 then
        local x, y = byte(d, addr + i * 2 + 1, addr + i * 2 + 2)
        l, a = x, y
      elseif siz == 1 then
        local v = byte(d, addr + i + 1)
        l, a = floor(v / 16) * 17, v % 16 * 17
      else
        local v = nibble(i)
        l, a = floor(floor(v / 2) * 255 / 7), (v % 2 == 1) and 255 or 0
      end
      out[i + 1] = char(l, l, l, a)
    end
  elseif fmt == 4 then                                
    for i = 0, n - 1 do
      local l = (siz == 1) and byte(d, addr + i + 1) or nibble(i) * 17
      out[i + 1] = char(l, l, l, 255)
    end
  else
    for i = 0, n - 1 do out[i + 1] = "\255\0\255\255" end
  end
  return w, h, concat(out)
end

StadiumFragment.decodeTexture = decodeTexture


local function compress(values, n, nd)
  local first = roundTo(values[1], nd)
  for i = 2, n do
    if roundTo(values[i], nd) ~= first then
      local out = {}
      for k = 1, n do out[k] = roundTo(values[k], nd) end
      return out
    end
  end
  return first
end

local function dedupeFx(nodes)
  local seen, out = {}, {}
  for i = 1, #nodes do
    local node = nodes[i]
    local key = tostring(node.commandOffset or "?") .. "," .. tostring(node.callback)
      .. "," .. tostring(node.arg)
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = {
        bone = node.bone,
        boneId = node.boneId,
        handler = node.handler or node.callback,
        callback = node.callback,
        arg = node.arg,
        argOffset = node.argOffset or node.arg,
        argPointer = node.argPointer,
        commandOffset = node.commandOffset,
        phase5Geometry = node.phase5Geometry,
        phase5DynamicState = node.phase5DynamicState,
      }
    end
  end
  return out
end

StadiumFragment.dedupeFx = dedupeFx

local function inspectFxLayout(frag, layoutOffset, layoutIndex, out, warnings)
  local state = { stack = { -1 }, boneIds = {}, bones = 0, steps = 0 }

  local function curBone()
    local n = #state.stack
    if n >= 2 then return state.stack[n - 1] end
    return -1
  end

  local function walk(o, depth)
    if depth > 32 then
      warnings[#warnings + 1] = ("geo %d exceeded recursion depth at 0x%X"):format(layoutIndex, o or -1)
      return
    end
    while type(o) == "number" do
      state.steps = state.steps + 1
      if state.steps > 100000 then
        warnings[#warnings + 1] = ("geo %d exceeded command budget"):format(layoutIndex)
        return
      end
      if o < 0 or o >= #frag.d then
        warnings[#warnings + 1] = ("geo %d left fragment at 0x%X"):format(layoutIndex, o)
        return
      end
      local cmd = frag:u8(o)
      local size = CMD_SIZES[cmd]
      if size == nil then
        warnings[#warnings + 1] = ("geo %d unknown command 0x%02X at 0x%X"):format(layoutIndex, cmd or -1, o)
        return
      end
      if o + size > #frag.d then
        warnings[#warnings + 1] = ("geo %d truncated command 0x%02X at 0x%X"):format(layoutIndex, cmd, o)
        return
      end

      if cmd == 0x01 or cmd == 0x04 then
        return
      elseif cmd == 0x00 or cmd == 0x03 then
        local target = frag:ptr(o + 4)
        if target == nil then
          warnings[#warnings + 1] = ("geo %d null branch at 0x%X"):format(layoutIndex, o)
        else
          walk(target, depth + 1)
        end
      elseif cmd == 0x02 then
        o = frag:ptr(o + 4)
        if o == nil then return end
        cmd = nil
      elseif cmd == 0x05 then
        local n = #state.stack
        state.stack[n + 1] = state.stack[n]
      elseif cmd == 0x06 then
        if #state.stack > 1 then state.stack[#state.stack] = nil end
      elseif cmd == 0x1D then
        local index = state.bones
        state.bones = index + 1
        state.boneIds[index] = frag:u8(o + 1)
        state.stack[#state.stack] = index
      elseif cmd == 0x08 then
        local bone = curBone()
        local argPointer = frag:u32(o + 8)
        local argOffset = nil
        if argPointer ~= 0 then
          local candidate = argPointer - BASE
          if candidate >= 0 and candidate < #frag.d then argOffset = candidate end
        end
        out[#out + 1] = {
          layout = layoutIndex,
          layoutOffset = layoutOffset,
          commandOffset = o,
          bone = bone,
          boneId = state.boneIds[bone],
          handler = frag:u32(o + 4),
          callback = frag:u32(o + 4),
          argPointer = argPointer,
          argOffset = argOffset,
        }
      end
      if cmd ~= nil then o = o + size end
    end
  end

  walk(layoutOffset, 0)
end

function StadiumFragment.inspectFx(data, name, sourceBase)
  if sourceBase ~= nil then StadiumFragment.setBase(sourceBase) end
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model, modelErr = pcall(newModel, frag)
  if not ok then return nil, tostring(model) end
  if not model then return nil, modelErr end
  local nodes, warnings = {}, {}
  for index, layoutOffset in ipairs(model.geoLayouts) do
    local walkOk, walkErr = pcall(inspectFxLayout, frag, layoutOffset, index, nodes, warnings)
    if not walkOk then
      warnings[#warnings + 1] = ("geo %d scan failed: %s"):format(index, tostring(walkErr))
    end
  end
  return {
    species = model.species,
    geometry = #model.geoLayouts,
    animations = #model.anims,
    auxiliary = #model.auxAnims,
    sourceBase = BASE,
    nodes = nodes,
    warnings = warnings,
  }
end

function StadiumFragment.extract(data, name, options)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local m, mErr = newModel(frag, options)
  if not m then return nil, mErr end
  m:build()
  if m.options.bakePhase5Geometry ~= false then m:bakePhase5Geometry() end
  m:mergePrimitivesByCallback()

  local auxAnims = {}
  for i = 1, #m.auxAnims do auxAnims[i] = newAux(frag, m.auxAnims[i]) end

  local texIndexMap, texOut = {}, {}
  local handlerTextures = {}

  local function register(texIdx, tlut, pal)
    local key = texIdx .. "," .. tlut .. "," .. pal
    local hit = texIndexMap[key]
    if hit ~= nil then return hit end
    if texIdx < 0 or texIdx >= #m.textures then return -1 end
    local slot = #texOut                              
    texIndexMap[key] = slot
    local tl = (tlut >= 0 and tlut < #m.tluts) and m.tluts[tlut + 1] or nil
    local source = m.textures[texIdx + 1]
    local w, h, rgba = decodeTexture(frag, source, tl, pal)
    texOut[slot + 1] = { index = texIdx, w = w, h = h, rgba = rgba,
      format = source.fmt, size = source.siz, texels = source.texels }
    return slot
  end

  local callbackTextureMap = {}
  local callbackTextureSites = {}
  local function registerCallback(node, pointer, w, h, fmt, siz, sampler, descriptorOffset)
    local offset = type(pointer) == "number" and pointer - BASE or nil
    local bytesPerPixel = siz == 3 and 4 or (siz == 2 and 2 or (siz == 1 and 1 or 0.5))
    local needed = math.ceil(w * h * bytesPerPixel)
    if not offset or offset < 0 or offset + needed > #frag.d then return nil end
    local key = table.concat({ pointer, w, h, fmt, siz }, ":")
    local slot = callbackTextureMap[key]
    if slot == nil then
      local _, _, rgba = decodeTexture(frag, { w = w, h = h, fmt = fmt, siz = siz, data = offset }, nil, 0)
      slot = #texOut
      callbackTextureMap[key] = slot
      texOut[slot + 1] = { index = -1, w = w, h = h, rgba = rgba,
        callback = true, sourcePointer = pointer, format = fmt, size = siz }
    end
    local site = tostring(node.commandOffset) .. ":" .. tostring(pointer)
    if not callbackTextureSites[site] then
      callbackTextureSites[site] = true
      handlerTextures[#handlerTextures + 1] = {
        commandOffset = node.commandOffset, pointer = pointer, slot = slot,
        w = w, h = h, format = fmt, size = siz,
        sampler = sampler, descriptorOffset = descriptorOffset,
      }
    end
    return slot
  end

  for _, p in ipairs(m.prims) do
    if p.ntris > 0 then
      local pal = m:tilePalette(p.mat)
      register(p.tex, p.tlut, pal)
      if p.texAnim >= 0 then
        for _, a in ipairs(auxAnims) do
          local tr, tn = a:track(p.texAnim)
          local vals, vn = unique(tr, tn)
          for i = 1, vn do register(vals[i], p.tlut, pal) end
        end
      end
    end
  end

  for _, node in ipairs(m.fx) do
    local arg = node.arg
    local handler = node.handler
    if arg then
      if handler == 0x81000038 then
        for i = 0, 7 do registerCallback(node, frag:u32(arg + 8 + i * 4), 32, 32, 3, 2) end
      elseif handler == 0x81000048 then
        registerCallback(node, frag:u32(arg), 32, 32, 0, 2)
        registerCallback(node, frag:u32(arg + 4), 32, 32, 0, 2)
      elseif handler == 0x81000050 then
        for i = 0, 7 do registerCallback(node, frag:u32(arg + 4 + i * 4), 32, 32, 0, 2) end
      elseif handler == 0x81000068 then
        for i = 0, 7 do registerCallback(node, frag:u32(arg + 4 + i * 4), 64, 32, 0, 2) end
      elseif handler == 0x81000070 then
        for i = 0, 7 do registerCallback(node, frag:u32(arg + 8 + i * 4), 32, 32, 4, 0) end
      elseif handler == 0x81000140 then
        for _, texture in ipairs(Phase5Geometry.textureSpecs(frag.d, BASE, arg)) do
          registerCallback(node, texture.pointer, texture.w, texture.h,
            texture.format, texture.size, texture.sampler, texture.descriptorOffset)
        end
      end
    end
  end


  local callbackTextureBySite, callbackStateBySite = {}, {}
  for _, row in ipairs(handlerTextures) do callbackTextureBySite[row.commandOffset] = row end
  for _, node in ipairs(m.fx) do
    if node.handler == 0x81000140 and node.arg then
      callbackStateBySite[node.commandOffset] = Phase5Geometry.stateSpec(frag.d, BASE, node.arg)
    end
  end

  local prims = {}
  for _, p in ipairs(m.prims) do
    if p.ntris > 0 then
      local pal = m:tilePalette(p.mat)
      local ti = texIndexMap[p.tex .. "," .. p.tlut .. "," .. pal] or -1
      local texMap = nil
      if p.texAnim >= 0 then
        for _, a in ipairs(auxAnims) do
          local tr, tn = a:track(p.texAnim)
          local vals, vn = unique(tr, tn)
          for i = 1, vn do
            local slot = texIndexMap[vals[i] .. "," .. p.tlut .. "," .. pal]
            if slot ~= nil then
              texMap = texMap or {}
              texMap[vals[i]] = slot
            end
          end
        end
      end
      local tw, th = 32, 32
      if ti >= 0 then
        tw, th = m.textures[p.tex + 1].w, m.textures[p.tex + 1].h
      end
      local pos, uv, nrm, color, skin, idx = {}, {}, {}, {}, {}, {}
      for i = 1, p.nverts do
        local v = p.verts[i]
        pos[i * 3 - 2], pos[i * 3 - 1], pos[i * 3] = v[1], v[2], v[3]
        uv[i * 2 - 1] = (v[4] / 32.0) / tw
        uv[i * 2] = (v[5] / 32.0) / th
        nrm[i * 3 - 2] = v[6] / 127.0
        nrm[i * 3 - 1] = v[7] / 127.0
        nrm[i * 3] = v[8] / 127.0
        color[i * 4 - 3] = v[6] < 0 and v[6] + 256 or v[6]
        color[i * 4 - 2] = v[7] < 0 and v[7] + 256 or v[7]
        color[i * 4 - 1] = v[8] < 0 and v[8] + 256 or v[8]
        color[i * 4] = v[9]
        skin[i] = v[10]
      end
      local ni = 0
      for i = 1, p.ntris do
        local tri = p.tris[i]
        idx[ni + 1], idx[ni + 2], idx[ni + 3] = tri[1], tri[2], tri[3]
        ni = ni + 3
      end
      -- Stadium 2 commonly leaves G_LIGHTING clear in these local display
      -- lists even though the Vtx payload contains signed normals.  Inferring
      -- the layout from that bit turns those normals into the rainbow RGB
      -- seen in the model viewer.  Classify the payload itself instead.
      local vertexSemantics = VertexSemantics.classify(nrm)
      local lighting = vertexSemantics == "normal"
      local callbackTexture = callbackTextureBySite[p.callbackOffset]
      local callbackState = callbackStateBySite[p.callbackOffset]
      local callbackTextureRequired = p.callbackOffset ~= nil and ti < 0
      local function textureHasAlpha(slot)
        local texture = slot and slot >= 0 and texOut[slot + 1] or nil
        local rgba = texture and texture.rgba
        if type(rgba) ~= "string" then return false end
        for alpha = 4, #rgba, 4 do
          if rgba:byte(alpha) < 255 then return true end
        end
        return false
      end
      local decal = textureHasAlpha(ti)
      if not decal then
        for _, slot in pairs(texMap or {}) do
          if textureHasAlpha(slot) then decal = true; break end
        end
      end
      -- Phase-5 state belongs to the callback-supplied texture surface. A
      -- node can also contain authored eye/face textures; propagating texgen
      -- onto those primitives replaces their atlas UVs with reflection UVs.
      local callbackGeometryMode = callbackTextureRequired and callbackState
        and callbackState.geometryMode or 0
      prims[#prims + 1] = {
        tex = ti, cull = floor((p.cull or 0) / 0x400) % 2 == 1,
        geometryMode = bor(p.cull or 0, callbackGeometryMode, 24), lighting = lighting,
        vertexSemantics = vertexSemantics,
        color = color, texAnim = p.texAnim, texMap = texMap,
        sampler = callbackTextureRequired and callbackTexture and callbackTexture.sampler or nil,
        textureScale = callbackTextureRequired and callbackState
          and callbackState.textureScale or nil,
        blend = (p.callbackDescriptor == 0x81000038 or p.callbackDescriptor == 0x81000068)
          and "add" or "alpha",
        materialOffset = p.mat, callbackOffset = p.callbackOffset,
        callbackDescriptor = p.callbackDescriptor,
        callbackTextureRequired = callbackTextureRequired,
        sourceTextureMissing = ti < 0,
        decal = decal and not callbackTextureRequired,
        pos = pos, uv = uv, nrm = nrm, skin = skin, nverts = p.nverts,
        idx = idx, nidx = ni,
      }
    end
  end

  -- The fire callbacks allocate their vertices at runtime through
  -- func_8007087C/func_80070974, so no triangles exist in the model DL to
  -- extract. Build only that missing billboard geometry here and feed it
  -- the eight textures extracted from the callback argument. Unlike the
  -- old importer stand-in, the pixels and frame order are Stadium 2 data.
  do
    local extent = Fx.modelExtent({ rootScale=m.rootScale, prims=prims })
    local scales = {}
    for i = 1, #m.bones do scales[i] = 1 end
    local texturesBySite = {}
    for _, row in ipairs(handlerTextures) do
      local list = texturesBySite[row.commandOffset]
      if not list then list = {}; texturesBySite[row.commandOffset] = list end
      list[#list + 1] = row.slot
    end
    for _, node in ipairs(m.fx) do
      local tail = node.handler == 0x81000038
      local small = node.handler == 0x81000068
      local slots = texturesBySite[node.commandOffset]
      if (tail or small) and slots and #slots > 0 and node.bone >= 0 then
        local scale = scales[node.bone + 1] or 1
        if scale == 0 then scale = 1 end
        local length = extent * (tail and 0.40 or 0.075) / scale
        local width = extent * (tail and 0.22 or 0.042) / scale
        local geo = Fx.crossedQuads(node.bone, length, width)
        prims[#prims + 1] = {
          tex = slots[1], cull = 0, texAnim = -1, texMap = nil,
          callbackOffset = node.commandOffset,
          generated = true, effect = "fire", blend = "add", fxFrames = slots,
          materialOffset = nil,
          pos = geo.pos, uv = geo.uv, nrm = geo.nrm, skin = geo.skin,
          nverts = geo.nverts, idx = geo.idx, nidx = geo.nidx,
        }
      end
    end
  end

  local anims = {}
  for i = 1, #m.anims do
    local a = newAnim(frag, m.anims[i])
    local nf = a.nFrames > 1 and a.nFrames or 1
    local tracks = {}
    for bi = 1, #m.bones do
      local b = m.bones[bi]
      local ch = b.chan
      if ch >= 0 and a:sampleTrs(ch, 0, b.t, b.r, b.s) ~= nil then
        local ts, rs, ss = {}, {}, {}
        for k = 1, 3 do ts[k], rs[k], ss[k] = {}, {}, {} end
        for fr = 0, nf - 1 do
          local t, r, s = a:sampleTrs(ch, fr, b.t, b.r, b.s)
          for k = 1, 3 do
            ts[k][fr + 1], rs[k][fr + 1], ss[k][fr + 1] = t[k], r[k], s[k]
          end
        end
        tracks[bi] = {
          t = { compress(ts[1], nf, 3), compress(ts[2], nf, 3),
                compress(ts[3], nf, 3) },
          r = { compress(rs[1], nf, 0), compress(rs[2], nf, 0),
                compress(rs[3], nf, 0) },
          s = { compress(ss[1], nf, 5), compress(ss[2], nf, 5),
                compress(ss[3], nf, 5) },
        }
      end
    end
    anims[i] = { index = i - 1, frames = nf, flags = a.flags,
                 startFrame = a.startFrame, channels = a.nChannels,
                 loopStart = a.loopStart,
                 tracks = tracks }
  end

  local auxOut = {}
  for i = 1, #auxAnims do
    local a = auxAnims[i]
    local chans = {}
    for c = 0, a.nChannels - 1 do
      local tr, tn = a:track(c)
      tr.n = tn
      chans[c + 1] = tr
    end
    local nf = a.nFrames > 1 and a.nFrames or 1
    auxOut[i] = { index = i - 1, frames = nf,
                  flags = a.flags, startFrame = a.startFrame,
                  loopStart = a.loopStart,
                  channels = chans }
  end

  return {
    species = m.species,
    file = name,
    rootScale = m.rootScale,
    bones = m.bones,
    textures = texOut,
    prims = prims,
    anims = anims,
    auxAnims = auxOut,
    fx = dedupeFx(m.fx),
    handlerTextures = handlerTextures,
    warnings = m.warnings,
  }
end


local function crystal251Inside(frag, off, size)
  return type(off) == "number" and off >= 0
    and off + (size or 1) <= #frag.d
end

local function crystal251LooksLikeAnim(frag, off, bones)
  if off % 4 ~= 0 or not crystal251Inside(frag, off, 0x1C) then return false end
  local flags = frag:u8(off)
  local startFrame = frag:u16(off + 4)
  local loopStart = frag:u16(off + 6)
  local nChannels = frag:u16(off + 8)
  local nFrames = frag:u16(off + 0xA)
  if flags > 0x0F or nChannels < 3 or nChannels > 0x600
      or nChannels % 3 ~= 0 or nFrames < 1 or nFrames > 0x1000
      or startFrame >= nFrames
      or (loopStart ~= 0xFFFF and loopStart >= nFrames) then
    return false
  end

  if type(bones) == "table" and #bones > 0 then
    local maxChan = -1
    for _, bone in ipairs(bones) do
      local chan = tonumber(bone.chan) or -1
      if chan > maxChan then maxChan = chan end
    end
    if maxChan >= 0 and nChannels < (maxChan + 1) * 3 then return false end
  end

  local chanTable = frag:ptr(off + 0xC)
  local scaleData = frag:ptr(off + 0x10)
  local rotData = frag:ptr(off + 0x14)
  local transData = frag:ptr(off + 0x18)
  if not crystal251Inside(frag, chanTable, nChannels * 0xA) then return false end

  local active, changing = 0, 0
  local needsScale, needsRot, needsTrans = false, false, false
  for channel = 0, nChannels - 1 do
    local row = chanTable + channel * 0xA
    local ns, nr, nt = frag:u8(row), frag:u8(row + 1), frag:u8(row + 2)
    local interp = frag:u8(row + 3)
    -- Upper interpolation bits are source flags in raw pose records. The
    -- three component decoders consume only bits 0..2, matching Anim:chan.
    if ns > 0 or nr > 0 or nt > 0 then active = active + 1 end
    if ns > 1 then needsScale, changing = true, changing + 1 end
    if nr > 1 then needsRot, changing = true, changing + 1 end
    if nt > 1 then needsTrans, changing = true, changing + 1 end
  end
  if active == 0 then return false end
  if needsScale and not crystal251Inside(frag, scaleData, 2) then return false end
  if needsRot and not crystal251Inside(frag, rotData, 2) then return false end
  if needsTrans and not crystal251Inside(frag, transData, 2) then return false end
  if nFrames > 1 and changing == 0 then return false end
  return true
end

local function crystal251RawAnimationOffsets(frag, bones)
  local found, seen = {}, {}
  local function add(off)
    if not seen[off] and crystal251LooksLikeAnim(frag, off, bones) then
      seen[off] = true
      found[#found + 1] = off
    end
  end

  local root = frag:root()
  if root then add(root) end
  local pointerEnd = math.min(#frag.d - 4, 0x1000)
  for o = 0x20, pointerEnd, 4 do
    local target = frag:ptr(o)
    if target and crystal251Inside(frag, target, 0x1C) then add(target) end
  end
  if #found == 0 then
    for off = 0x20, #frag.d - 0x1C, 4 do add(off) end
  end
  table.sort(found)
  return found
end

local function crystal251DecodeOne(frag, off, bones)
  local a = newAnim(frag, off)
  local nf = a.nFrames > 1 and a.nFrames or 1
  local tracks, trackCount = {}, 0
  for bi = 1, #bones do
    local b = bones[bi]
    local ch = tonumber(b.chan) or -1
    local bt = type(b.t) == "table" and b.t or { 0, 0, 0 }
    local br = type(b.r) == "table" and b.r or { 0, 0, 0 }
    local bs = type(b.s) == "table" and b.s or { 1, 1, 1 }
    if ch >= 0 and a:sampleTrs(ch, 0, bt, br, bs) ~= nil then
      local ts, rs, ss = {}, {}, {}
      for k = 1, 3 do ts[k], rs[k], ss[k] = {}, {}, {} end
      for fr = 0, nf - 1 do
        local t, r, sc = a:sampleTrs(ch, fr, bt, br, bs)
        for k = 1, 3 do
          ts[k][fr + 1], rs[k][fr + 1], ss[k][fr + 1] =
            t[k], r[k], sc[k]
        end
      end
      tracks[bi] = {
        t = { compress(ts[1], nf, 3), compress(ts[2], nf, 3),
              compress(ts[3], nf, 3) },
        r = { compress(rs[1], nf, 0), compress(rs[2], nf, 0),
              compress(rs[3], nf, 0) },
        s = { compress(ss[1], nf, 5), compress(ss[2], nf, 5),
              compress(ss[3], nf, 5) },
      }
      trackCount = trackCount + 1
    end
  end
  if #bones > 0 and trackCount == 0 then
    return nil, ("animation@0x%X has no channels used by this skeleton "
      .. "(file-channels=%d bones=%d)"):format(off, a.nChannels, #bones)
  end
  return {
    index = 0,
    frames = nf,
    flags = a.flags,
    startFrame = a.startFrame,
    channels = a.nChannels,
    loopStart = a.loopStart,
    tracks = tracks,
    sourceOffset = off,
  }
end

local function crystal251DecodeOffsets(frag, offsets, bones)
  bones = type(bones) == "table" and bones or {}
  local anims, errors = {}, {}
  for _, off in ipairs(offsets or {}) do
    local ok, animation, reason = pcall(crystal251DecodeOne, frag, off, bones)
    if ok and animation then
      animation.index = #anims
      anims[#anims + 1] = animation
    else
      errors[#errors + 1] = ("animation@0x%X: %s")
        :format(off, tostring(ok and reason or animation))
    end
  end
  return anims, errors
end

local function crystal251DecodeModelAnimations(frag, model, bones)
  local anims, errors = crystal251DecodeOffsets(frag, model.anims, bones)
  local aux = {}
  for i = 1, #model.auxAnims do
    local ok, a = pcall(newAux, frag, model.auxAnims[i])
    if ok and a then
      local channels = {}
      for c = 0, a.nChannels - 1 do
        local track, n = a:track(c)
        track.n = n
        channels[c + 1] = track
      end
      local nf = a.nFrames > 1 and a.nFrames or 1
      aux[#aux + 1] = {
        index = #aux,
        frames = nf,
        flags = a.flags,
        startFrame = a.startFrame,
        loopStart = a.loopStart,
        channels = channels,
      }
    end
  end
  return anims, aux, errors
end

function StadiumFragment.inspect(data, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model, modelErr = pcall(newModel, frag)
  if ok and model then
    return {
      species = model.species,
      geometry = #model.geoLayouts,
      animations = #model.anims,
      auxiliary = #model.auxAnims,
      rootKind = "model",
    }
  end
  return nil, ok and modelErr or model
end

function StadiumFragment.inspectAny(data, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model = pcall(newModel, frag)
  if ok and model then
    local raw = #model.anims == 0 and crystal251RawAnimationOffsets(frag) or {}
    return {
      species = model.species,
      geometry = #model.geoLayouts,
      animations = math.max(#model.anims, #raw),
      auxiliary = #model.auxAnims,
      rootKind = #model.anims > 0 and "model" or (#raw > 0 and "raw-motion" or "model"),
      rawAnimationOffsets = raw,
    }
  end
  local raw = crystal251RawAnimationOffsets(frag)
  if #raw == 0 then return nil, tostring(model or "unrecognised FRAGMENT root") end
  local root = frag:root()
  local species = root and crystal251Inside(frag, root, 2) and frag:u16(root) or 0
  return {
    species = species,
    geometry = 0,
    animations = #raw,
    auxiliary = 0,
    rootKind = "raw-motion",
    rawAnimationOffsets = raw,
  }
end

function StadiumFragment.extractAnimations(data, bones, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local model, modelErr = newModel(frag)
  if not model then return nil, modelErr end
  local anims, aux, errors = crystal251DecodeModelAnimations(frag, model, bones)
  return {
    species = model.species,
    anims = anims,
    auxAnims = aux,
    errors = errors,
  }
end

function StadiumFragment.extractAnimationsAny(data, bones, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model = pcall(newModel, frag)
  if ok and model and (#model.anims > 0 or #model.auxAnims > 0) then
    local anims, aux, errors = crystal251DecodeModelAnimations(frag, model, bones)
    return { species=model.species, anims=anims, auxAnims=aux, errors=errors }
  end
  local offsets = crystal251RawAnimationOffsets(frag, bones)
  if #offsets == 0 then return nil, tostring(model or "no skeletal animation headers") end
  local anims, errors = crystal251DecodeOffsets(frag, offsets, bones)
  if #anims == 0 then return nil, table.concat(errors, " | ") end
  local root = frag:root()
  local species = root and crystal251Inside(frag, root, 2) and frag:u16(root) or 0
  return { species=species, anims=anims, auxAnims={}, errors=errors }
end


local RawFrag = {}
RawFrag.__index = RawFrag
setmetatable(RawFrag, { __index = Frag })

function RawFrag:off(ptr)
  if ptr == 0 then return nil end
  if self.pointerMode == "file" then return ptr end
  if self.pointerMode == "header" then return self.headerOffset + ptr end
  if self.pointerMode == "low24" then return ptr % 0x1000000 end
  return ptr - (self.pointerBase or 0)
end

function RawFrag:ptr(o)
  return self:off(self:u32(o))
end

local function crystal251HexPrefix(data, count)
  local out = {}
  for i = 1, math.min(#data, count or 32) do
    out[#out + 1] = ("%02X"):format(data:byte(i))
  end
  return table.concat(out)
end

local function crystal251RawModes(data, headerOffset)
  local modes, seen = {}, {}
  local function add(mode, base, label)
    local key = mode .. ":" .. tostring(base or 0)
    if seen[key] then return end
    seen[key] = true
    modes[#modes + 1] = { mode=mode, base=base or 0, label=label or key }
  end
  add("file", 0, "file-offset")
  add("header", 0, "header-relative")
  add("low24", 0, "low24")

  local pointers = {}
  for o = 0xC, 0x18, 4 do
    local at = headerOffset + o
    if at + 4 <= #data then
      local a,b,c,d = data:byte(at + 1, at + 4)
      local value = ((a * 256 + b) * 256 + c) * 256 + d
      if value ~= 0 then pointers[#pointers + 1] = value end
    end
  end
  for pointerIndex, ptr in ipairs(pointers) do
    for _, align in ipairs({ 0x1000, 0x10000, 0x100000 }) do
      local base = math.floor(ptr / align) * align
      add("base", base, ("base-0x%X"):format(base))
    end
    if pointerIndex == 1 then
      local alignedHeaderEnd = math.floor((headerOffset + 0x1F) / 4) * 4
      for _, target in ipairs({
          alignedHeaderEnd, headerOffset + 0x20,
          0x20, 0x30, 0x40, 0x80, 0x100,
        }) do
        if target >= 0 and target < #data then
          local base = ptr - target
          add("base", base, ("derived-0x%X"):format(base))
        end
      end
    end
  end
  return modes
end

local function crystal251RawU32(data, offset)
  local a, b, c, d = byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function crystal251RawCandidates(data, bones)
  local found, seen = {}, {}
  if type(data) ~= "string" or #data < 0x1C then return found end
  local function probe(off)
    for _, mode in ipairs(crystal251RawModes(data, off)) do
      local frag = setmetatable({
        d=data, name="<raw Stadium 2 pose>", headerOffset=off,
        pointerMode=mode.mode, pointerBase=mode.base,
      }, RawFrag)
      if crystal251LooksLikeAnim(frag, off, bones) then
        local key = off .. ":" .. mode.label
        if not seen[key] then
          seen[key] = true
          found[#found + 1] = {
            frag=frag, off=off, mode=mode.label,
          }
        end
      end
    end
  end

  local footer = crystal251RawU32(data, 0)
  if footer and footer % 4 == 0 and footer >= 0
      and footer + 0x1C <= #data then
    probe(footer)
    if #found > 0 then return found end
  end

  local prefixEnd = math.min(#data - 0x1C, 0x80)
  for off = 0, prefixEnd, 4 do probe(off) end
  return found
end

function StadiumFragment.inspectRawAnimations(data, name)
  local candidates = crystal251RawCandidates(data)
  if #candidates == 0 then
    return nil, ("raw pose has no animation header (bytes=%d head=%s)")
      :format(type(data) == "string" and #data or 0,
        type(data) == "string" and crystal251HexPrefix(data, 32) or "")
  end
  local offsets, modes = {}, {}
  for _, candidate in ipairs(candidates) do
    offsets[candidate.off] = true
    modes[candidate.mode] = true
  end
  local nOffsets, nModes = 0, 0
  for _ in pairs(offsets) do nOffsets = nOffsets + 1 end
  for _ in pairs(modes) do nModes = nModes + 1 end
  return {
    species = 0,
    geometry = 0,
    animations = nOffsets,
    auxiliary = 0,
    rootKind = "raw-pose",
    pointerModes = nModes,
  }
end

function StadiumFragment.extractRawAnimations(data, bones, name)
  local candidates = crystal251RawCandidates(data, bones)
  if #candidates == 0 then
    return nil, ("raw pose has no skeleton-compatible animation header "
      .. "(bytes=%d head=%s)"):format(type(data) == "string" and #data or 0,
        type(data) == "string" and crystal251HexPrefix(data, 32) or "")
  end
  local anims, errors, usedOffsets = {}, {}, {}
  for _, candidate in ipairs(candidates) do
    if not usedOffsets[candidate.off] then
      local ok, animation, reason = pcall(crystal251DecodeOne,
        candidate.frag, candidate.off, bones or {})
      if ok and animation then
        usedOffsets[candidate.off] = true
        animation.index = #anims
        animation.rawPose = true
        animation.pointerMode = candidate.mode
        anims[#anims + 1] = animation
      else
        errors[#errors + 1] = ("raw-animation@0x%X[%s]: %s")
          :format(candidate.off, candidate.mode,
            tostring(ok and reason or animation))
      end
    end
  end
  if #anims == 0 then return nil, table.concat(errors, " | ") end
  return { species=0, anims=anims, auxAnims={}, errors=errors }
end

return StadiumFragment
