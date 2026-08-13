package.path = "./?.lua;./?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Palette = require("mods.STADIUM2_IMPORTER.lib.palette")
local Cache = require("mods.STADIUM2_IMPORTER.lib.cache")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local z64 = "\128\055\018\064" .. string.rep("\0", 0x1000)
local normalized, order = Rom.normalise(z64)
ok(normalized == z64 and order == "z64", "z64 byte order")

local v64 = "\055\128\064\018" .. string.rep("\0", 0x1000)
local vnorm, vorder = Rom.normalise(v64)
ok(vnorm:sub(1, 4) == "\128\055\018\064" and vorder == "v64", "v64 byte order")

local n64 = "\064\018\055\128" .. string.rep("\0", 0x1000)
local nnorm, norder = Rom.normalise(n64)
ok(nnorm:sub(1, 4) == "\128\055\018\064" and norder == "n64", "n64 byte order")

ok(Extract.MAX_COUNT == 251, "extractor supports 251 species")
Extract.configure({ count = 999 })
ok(Extract.COUNT == 251, "extractor count is capped at 251")
ok(Extract.UNOWN_EXTRA_FORMS==25 and Extract.UNOWN_FORM_FIRST==254
  and Extract.UNOWN_FORM_LAST==278,"extractor includes Unown B through Z records")
ok(Extract.unownLetter(254)=="B" and Extract.unownLetter(278)=="Z",
  "Stadium 2 extra records map to the complete Unown alphabet")
ok(Cache.unownPath("B","normal")=="stadium2_importer/battle/unown_b.dsm"
  and Cache.unownPath("Z","shiny")=="stadium2_importer/battle/unown_z_shiny.dsm",
  "normal and shiny Unown form packs have stable cache paths")
ok(Cache.FORMAT=="S2IMP18",
  "Koffing I4 callback texture fix invalidates older extracted model packs")
ok(Pack.validSpecies(254) and Pack.validSpecies(278)
  and not Pack.validSpecies(252) and not Pack.validSpecies(279),
  "DSM parser accepts exactly the Stadium 2 Unown form record range")
ok(type(Palette.recolour) == "function", "standalone shiny recoloring exists")
local pidgeyRare = Palette.decodeRare(string.char(0x0A, 0x00, 0xFE, 0x01), 0)
ok(pidgeyRare and pidgeyRare.hue == 40 and pidgeyRare.saturation == -2
  and pidgeyRare.lightness == 1,
  "Stadium species metadata decodes signed rare HSL values")
local dedicatedRare = Palette.decodeRare("\255\255\255\255", 0)
ok(dedicatedRare and dedicatedRare.specialTexture == true,
  "Stadium dedicated rare-texture sentinel is recognized")
local shifted = Palette.applyRare(
  string.char(255, 230, 164, 255, 90, 247, 186, 128), pidgeyRare)
ok(shifted == string.char(231, 251, 200, 255, 90, 247, 186, 128),
  "rare HSL transforms opaque model texels without recoloring translucent FX")
local rgba5551 = assert(Palette.decodeRgba5551(
  string.char(0xFF, 0xFF, 0xF8, 0x01, 0x07, 0xC1, 0x00, 0x3F), 4))
ok(rgba5551 == string.char(255,255,255,255, 255,0,0,255,
    0,255,0,255, 0,0,255,255),
  "dedicated RGBA16 texture components decode from N64 RGBA5551")
local badDedicated, badDedicatedErr = Palette.decodeRgba5551("\0\0", 2)
ok(badDedicated == nil and type(badDedicatedErr) == "string",
  "dedicated rare-texture sizes are validated")
local wigglytuffNative = Palette.nativeTextureBytes(4, 4, 2)
  + 12 * Palette.nativeTextureBytes(32, 32, 2)
  + Palette.nativeTextureBytes(4, 4, 1)
ok(wigglytuffNative == 24624,
  "Wigglytuff dedicated textures use native N64 bit depths")
local i8 = assert(Palette.decodeNativeTexture(
  string.char(0, 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255),
  4, 4, 4, 1))
ok(#i8 == 64 and i8:sub(1, 4) == string.char(0, 0, 0, 255)
  and i8:sub(61, 64) == string.char(255, 255, 255, 255),
  "dedicated I8 textures decode at one source byte per pixel")

local scanJob = Extract.newJob("", function() return true end)
local scanOk = pcall(function() scanJob:step() end)
ok(scanOk, "exact-root extraction scan has layout constants")

print(("%d checks passed (Stadium 2 core)"):format(checks))
