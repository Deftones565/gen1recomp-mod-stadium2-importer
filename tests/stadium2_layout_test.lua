package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function be32(value)
  local a = math.floor(value / 0x1000000) % 0x100
  local b = math.floor(value / 0x10000) % 0x100
  local c = math.floor(value / 0x100) % 0x100
  local d = value % 0x100
  return string.char(a, b, c, d)
end

local function archive(tag, relative, size, reserved1, reserved2)
  return be32(tag) .. be32(0) .. be32(0x40) .. be32(1)
    .. be32(relative) .. be32(size) .. be32(reserved1 or 0) .. be32(reserved2 or 0)
    .. string.rep("\0", 0x20)
end

ok(Layout.ASSET_START == 0x437610, "current decomp opaque tail boundary")
ok(Layout.FRAGMENT26_ROM_START == 0x15E8B0, "fragment26 ROM start")
ok(Layout.FRAGMENT26_ROM_END == 0x165C50, "fragment26 ROM end")
ok(Layout.FRAGMENT26_VRAM == 0x81000000, "fragment26 VRAM base")
ok(Layout.FRAGMENT26_TABLE_START == 0x81000020, "fragment26 table start")
ok(Layout.FRAGMENT26_TABLE_END == 0x81000180, "fragment26 table end")
ok(Layout.FRAGMENT26_CODE_START == 0x81000180, "fragment26 code start")
ok(Layout.MODEL_TABLE_START == 0x27ED000, "model region start")
ok(Layout.MODEL_TABLE_END == 0x2D7D000, "model region end")
ok(Layout.POSE_TABLE_START == 0x2D7D000, "pose region start")
ok(Layout.POSE_TABLE_END == 0x3FD5000, "pose region end")
ok(Layout.SPECIES_META_START == 0x3FED000, "species metadata candidate start")

local valid = Rom.archiveAt(archive(0xEF, 0x20, 0x20), 0)
ok(valid and valid.tag == 0xEF and valid.count == 1, "cattbl -f archive accepted")
ok(Rom.archiveAt(archive(0, 0x20, 0x20), 0) ~= nil, "cattbl archive accepted")
ok(Rom.archiveAt(archive(0xEE, 0x20, 0x20), 0) == nil, "unknown archive tag rejected")
ok(Rom.archiveAt(archive(0xEF, 0x20, 0x20, 1, 0), 0) == nil, "reserved word one rejected")
ok(Rom.archiveAt(archive(0xEF, 0x20, 0x20, 0, 1), 0) == nil, "reserved word two rejected")
ok(Rom.archiveAt(archive(0xEF, 0x21, 0x10), 0) == nil, "misaligned record offset rejected")
ok(Rom.archiveAt(archive(0xEF, 0x20, 0x11), 0) == nil, "misaligned record size rejected")

print(("%d checks passed (Stadium 2 layout)"):format(checks))
