package.path = "./?.lua;./?/init.lua;" .. package.path

local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function be16(v)
  v = v % 0x10000
  return string.char(math.floor(v / 0x100) % 0x100, v % 0x100)
end

local function be32(v)
  v = v % 0x100000000
  return string.char(math.floor(v / 0x1000000) % 0x100,
    math.floor(v / 0x10000) % 0x100,
    math.floor(v / 0x100) % 0x100, v % 0x100)
end

local function blob(size)
  local b = {}
  for i = 1, size do b[i] = "\0" end
  local function put(off, bytes)
    for i = 1, #bytes do b[off + i] = bytes:sub(i, i) end
  end
  return b, put
end

local function finish(b) return table.concat(b) end

local bones = {
  { chan = 0, t = { 0, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } },
}

-- Stadium's player keeps one absolute frame counter. Header +4 initializes
-- that counter; the packed/Hermite samplers index their streams with the
-- counter directly. Therefore extraction must preserve frames 0..end-1 rather
-- than adding startFrame a second time. Header +6 is already the loop target
-- in that same frame space.
do
  local b, put = blob(0x70)
  put(0x00, be16(8))       -- Hermite/keyframed TRS
  put(0x04, be16(5))       -- initial playback frame
  put(0x06, be16(2))       -- loop target
  put(0x08, be16(3))       -- one XYZ channel triplet
  put(0x0A, be16(7))       -- end / frame count
  put(0x0C, be32(0x20))
  put(0x10, be32(0))
  put(0x14, be32(0))
  put(0x18, be32(0x50))
  put(0x20, string.char(0, 0, 2, 0) .. be16(0) .. be16(0) .. be16(0))
  put(0x2A, string.rep("\0", 10))
  put(0x34, string.rep("\0", 10))
  put(0x50, be16(0) .. be16(100) .. be16(0)
          .. be16(6) .. be16(700) .. be16(0))

  local out, err = Fragment.extractRawAnimations(finish(b), bones, "timeline-key")
  ok(out ~= nil, "keyframed animation decodes: " .. tostring(err))
  local anim = out.anims[1]
  local x = anim.tracks[1].t[1]
  ok(type(x) == "table" and #x == 7, "keyframed stream exports all seven source frames")
  ok(x[1] == 100 and x[7] == 700,
    "keyframed sampling uses the playback counter directly, without adding startFrame")
  ok(anim.startFrame == 5, "initial playback frame remains available for audit")
  ok(anim.frames == 7, "header end/frame count remains the exported frame count")
  ok(anim.loopStart == 2, "loop target remains in the source counter's frame space")
end

-- Packed tracks follow the identical counter rule.
do
  local b, put = blob(0x80)
  put(0x00, be16(0))
  put(0x04, be16(5))
  put(0x06, be16(2))
  put(0x08, be16(3))
  put(0x0A, be16(7))
  put(0x0C, be32(0x20))
  put(0x10, be32(0x50))
  put(0x14, be32(0))
  put(0x18, be32(0))
  put(0x20, string.char(7, 0, 0, 0) .. be16(0) .. be16(0) .. be16(0))
  put(0x2A, string.rep("\0", 10))
  put(0x34, string.rep("\0", 10))
  local scales = { 1000, 1100, 1200, 1300, 1400, 1500, 1600 }
  local bytes = {}
  for i = 1, #scales do bytes[i] = be16(scales[i]) end
  put(0x50, table.concat(bytes))

  local out, err = Fragment.extractRawAnimations(finish(b), bones, "timeline-packed")
  ok(out ~= nil, "packed animation decodes: " .. tostring(err))
  local anim = out.anims[1]
  local sx = anim.tracks[1].s[1]
  ok(type(sx) == "table" and #sx == 7 and sx[1] == 1.0 and sx[6] == 1.5
      and sx[7] == 1.6,
    "packed stream is not shifted/clamped by the initial playback frame")
  ok(anim.loopStart == 2, "packed loop target is preserved")
end

-- Texture/auxiliary streams are driven by the same frame counter.
do
  Fragment.setBase(0x8FF00000)
  local b, put = blob(0x190)
  put(0x08, "FRAGMENT")
  put(0x20, be32(0x3C088FF0))
  put(0x24, be32(0x25080100))
  put(0x100, be16(25))
  put(0x108, be32(0))
  put(0x10C, be32(0))
  put(0x110, be32(0x8FF00120))
  put(0x120, be32(0x8FF00140))
  put(0x124, be32(0))

  put(0x140, be16(0))
  put(0x144, be16(5))
  put(0x146, be16(2))
  put(0x148, be16(1))
  put(0x14A, be16(7))
  put(0x14C, be32(0x8FF00160))
  put(0x150, be32(0x8FF00170))
  put(0x160, be16(7) .. be16(0))
  put(0x170, string.char(10, 11, 12, 13, 14, 15, 16))

  local out, err = Fragment.extractAnimations(finish(b), bones, "timeline-aux")
  ok(out ~= nil, "auxiliary animation decodes: " .. tostring(err))
  local aux = out.auxAnims[1]
  ok(aux and #aux.channels[1] == 7 and aux.channels[1][1] == 10
      and aux.channels[1][6] == 15 and aux.channels[1][7] == 16,
    "auxiliary stream is indexed by the same unshifted playback counter")
  ok(aux and aux.startFrame == 5, "auxiliary initial playback frame is retained")
  ok(aux and aux.loopStart == 2, "auxiliary loop target remains absolute")
end

print(("%d checks passed (Stadium 2 animation counter semantics)"):format(checks))
