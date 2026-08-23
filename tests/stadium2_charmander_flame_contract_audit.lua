package.path = "./?.lua;./?/init.lua;" .. package.path

-- ROM-to-renderer contract for fragment 26 descriptor 0x81000038. This test
-- intentionally keeps its expected mesh, display-list words, texture decode,
-- and material equations independent of lib/render_callbacks/flame.lua.

local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Flame = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.flame")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Palette = require("mods.STADIUM2_IMPORTER.lib.palette")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_charmander_flame_contract_audit.lua\n")
  os.exit(2)
end

local failures, checks = {}, 0
local function check(value, message)
  checks = checks + 1
  if not value then failures[#failures + 1] = message end
end
local function close(a, b, epsilon)
  return math.abs((a or 0) - (b or 0)) <= (epsilon or 0.000001)
end
local function same(a, b, epsilon)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if not close(a[i], b[i], epsilon) then return false end end
  return true
end
local function u16(bytes, offset)
  local a, b = bytes:byte(offset + 1, offset + 2)
  return a and a * 256 + b or nil
end
local function i16(bytes, offset)
  local value = u16(bytes, offset)
  return value and (value >= 0x8000 and value - 0x10000 or value) or nil
end
local function u32(bytes, offset)
  local a, b, c, d = bytes:byte(offset + 1, offset + 4)
  return d and ((a * 256 + b) * 256 + c) * 256 + d or nil
end
local function words(bytes, offset, count)
  local out = {}
  for i = 0, count - 1 do out[#out + 1] = u32(bytes, offset + i * 4) end
  return out
end
local function containsWord(bytes, value)
  for offset = 0, #bytes - 4, 4 do
    if u32(bytes, offset) == value then return true end
  end
  return false
end

local file = assert(io.open(path, "rb"))
local data = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(data, Layout.MODEL_TABLE_START))
local MAIN_DELTA = 0x7FFFF400
local function mainOffset(address) return address - MAIN_DELTA end

-- Descriptor and callback control flow: phase 2, one shared display counter,
-- modulo eight, then the texture/object builder.
local descriptor = assert(Fragment26.descriptor(data, Flame.DESCRIPTOR))
check(descriptor.target == 0x81005AC0 and descriptor.word1 == 0,
  "descriptor 0x81000038 no longer jumps to func_81005AC0")
local callback = assert(Fragment26.functionBytes(data, 0x81005AC0))
check(containsWord(callback, 0x24010002), "flame callback lost its phase-2 gate")
check(containsWord(callback, 0x95CE4904), "flame callback no longer reads counter 0x80094904")
check(containsWord(callback, 0x30C60007), "flame callback no longer selects counter modulo eight")
check(containsWord(callback, 0x0C401674), "flame callback no longer calls func_810059D0")

-- Exact RDP state emitted by func_810059D0 and the two shared display lists.
local builder = assert(Fragment26.functionBytes(data, 0x810059D0))
for _, word in ipairs({
  0x3C0EFD70, -- G_SETTIMG IA16
  0x3C0AF570, 0x356B0200, -- load tile
  0x3C18F568, 0x37180800, 0x37390200, -- render tile, clamp/clamp
  0x3C0AF200, 0x356BC0FC, -- 32x64 render-tile size
  0x0C01C21F, 0x0C01C25D, -- prepare and draw shared object
  0x3C0CD9FF, 0x358CFFFF, 0x3C0D0002, -- restore geometry mode
}) do
  check(containsWord(builder, word), ("func_810059D0 lost instruction word %08X"):format(word))
end

local stateWords = words(data, mainOffset(0x8009F410), 6)
check(same(stateWords, {
  0xE3000A01, 0x00100000, -- G_CYC_2CYCLE
  0xE7000000, 0x00000000,
  0xDF000000, 0x00000000,
}), "shared flame state display list is not the ROM two-cycle state")
local materialWords = words(data, mainOffset(0x8009F448), 10)
check(same(materialWords, {
  0xD9FDFFFF, 0x00000000, -- clear lighting
  0xE7000000, 0x00000000,
  0xFC309680, 0x5F1AFFFF, -- exact two-cycle combiner
  0xE3001001, 0x00000000, -- G_TT_NONE
  0xDF000000, 0x00000000,
}), "shared flame material display list differs from the ROM")

local species = {}
for offset = 0, 24, 2 do species[#species + 1] = i16(data,
  mainOffset(0x8009F428) + offset) end
check(same(species, {4,5,6,126,146,109,110,77,78,144,134,92,-1}),
  "shared flame species dispatch table differs from the ROM")

-- Exact Vtx payload and triangle order. These constants are independent of
-- Flame.geometry so a convenient strip reconstruction cannot pass this test.
local expectedVertex = {
  {-50,200,0,   0,   0,255,255,  0,255},
  {-50,150,0,   0, 512,255,255,  0,255},
  { 50,150,0,1024, 512,255,255,  0,255},
  { 50,200,0,1024,   0,255,255,  0,255},
  {-50,100,0,   0,1024,255,255,  0,255},
  { 50,100,0,1024,1024,255,255,  0,255},
  {-50, 50,0,   0,1536,255,255,192,255},
  { 50, 50,0,1024,1536,255,255,192,255},
  {-50,  0,0,   0,2048,255,255,128,255},
  { 50,  0,0,1024,2048,255,255,128,255},
}
local expectedPos, expectedUV, expectedColor = {}, {}, {}
local vertexOffset = mainOffset(0x8009F228)
for i, expected in ipairs(expectedVertex) do
  local offset = vertexOffset + (i - 1) * 16
  local actual = {i16(data,offset),i16(data,offset+2),i16(data,offset+4),
    i16(data,offset+8),i16(data,offset+10),
    data:byte(offset+13,offset+16)}
  check(same(actual, expected), ("shared flame Vtx %d differs from ROM contract"):format(i))
  expectedPos[#expectedPos+1] = expected[1]
  expectedPos[#expectedPos+1] = expected[2]
  expectedPos[#expectedPos+1] = expected[3]
  expectedUV[#expectedUV+1] = expected[4]/1024
  expectedUV[#expectedUV+1] = expected[5]/2048
  for c = 6, 9 do expectedColor[#expectedColor+1] = expected[c] end
end
local expectedIndex = {1,2,3,1,3,4,2,5,6,2,6,3,5,7,8,5,8,6,7,9,10,7,10,8}
check(same(words(data, mainOffset(0x8009F2E0), 12), {
  0x0100A014,0x0E000000,0x06000204,0x00000406,0x0602080A,0x00020A04,
  0x06080C0E,0x00080E0A,0x060C1012,0x000C120E,0xDF000000,0x00000000,
}), "shared flame geometry display list differs from the ROM")
local geometry = Flame.geometry(7)
check(same(geometry.pos, expectedPos) and same(geometry.uv, expectedUV)
    and same(geometry.color, expectedColor) and same(geometry.idx, expectedIndex),
  "portable flame geometry does not reproduce the literal ROM Vtx/triangles")

-- All renderer shader paths must implement the same combiner result:
-- RGB = SHADE * mix(ENVIRONMENT, PRIMITIVE, IA intensity)
-- A   = IA8 alpha * PRIMITIVE_ALPHA. I4 particles remain mode 1.
for name, source in pairs({desktop=Renderer.SHADER_SOURCE,
    mobile=Renderer.MOBILE_SHADER_SOURCE, fallback=Renderer.CAMERA_SHADER_SOURCE}) do
  check(source:find("effectIntensityMode > 1.5", 1, true) ~= nil
      and source:find("texel.a", 1, true) ~= nil,
    name .. " shader does not use IA8 alpha for flame coverage")
  check(source:find("mix(environmentColor.rgb, primitiveColor.rgb, intensity)", 1, true) ~= nil
      or source:find("mix(environmentColor.rgb,primitiveColor.rgb,intensity)", 1, true) ~= nil,
    name .. " shader does not implement the ROM flame RGB combiner")
  check(source:find("(1.0 - VertexTexCoord.y) * billboardSize.y",1,true) ~= nil
      and source:find("VertexTexCoord.y * 0.5",1,true) == nil,
    name .. " shader does not place T=1 at the tail attachment")
end

-- Billboarding keeps translation and scale from the attachment matrix while
-- replacing its rotation with the camera axes. Validate the exact 100x200
-- card using the ROM vertex order (top corners are records 1 and 4).
local billboardRows = {}
for i, vertex in ipairs(expectedVertex) do
  billboardRows[i] = {vertex[1],vertex[2],vertex[3]}
end
local sent = {}
Renderer.sendFlameBillboard({send=function(_,name,value) sent[name]=value end},
  {prim={effect="fire"},rows=billboardRows}, Renderer.identity(), Renderer.identity())
check(sent.billboardEnabled == 1 and same(sent.billboardCenter,{0,0,0})
    and same(sent.billboardSize,{100,200}) and same(sent.billboardRight,{1,0,0})
    and same(sent.billboardUp,{0,1,0}),
  "renderer does not reproduce the shared object's 100x200 camera-facing transform")

local sharedFrameBytes
local expectedBones = {[4]=11,[5]=8,[6]=6}
for _, dex in ipairs({4,5,6}) do
  local decoded = assert(Rom.decompress(assert(Rom.recordBytes(data,
    archive.records[dex + 1]))))
  local info = assert(Extract.fragmentInfo(decoded))
  Fragment.setBase(info.sourceBase)
  local runtime = Extract.runtimeFragmentForSpecies(data,dex,decoded)
  local model = assert(Fragment.extract(runtime,("flame-contract-%03d"):format(dex)))
  local fxInfo = assert(Fragment.inspectFx(decoded,"flame-contract",info.sourceBase))
  local node
  for _, value in ipairs(fxInfo.nodes or {}) do
    if value.handler == Flame.DESCRIPTOR then
      check(node == nil, ("dex %03d has multiple flame callback commands"):format(dex))
      node = value
    end
  end
  check(node and node.bone == expectedBones[dex] and node.argOffset ~= nil,
    ("dex %03d flame callback is attached to the wrong ROM bone"):format(dex))

  local flamePrim
  for _, prim in ipairs(model.prims or {}) do
    if prim.effect == "fire" then
      check(flamePrim == nil, ("dex %03d generated multiple flame cards"):format(dex))
      flamePrim = prim
    end
  end
  check(flamePrim and flamePrim.blend == "add" and flamePrim.cull == 0
      and flamePrim.nverts == 10 and flamePrim.nidx == 24
      and same(flamePrim.pos,expectedPos) and same(flamePrim.uv,expectedUV)
      and same(flamePrim.color,expectedColor) and same(flamePrim.idx,expectedIndex),
    ("dex %03d generated flame output is not the complete shared object"):format(dex))
  local matrices=Build.bindMatrices(model.bones)
  local attachment=matrices[node.bone+1]
  local rootScale=model.rootScale[1]
  local function point(vertex)
    local x,y,z=flamePrim.pos[vertex*3-2],flamePrim.pos[vertex*3-1],
      flamePrim.pos[vertex*3]
    return {
      (attachment[1][1]*x+attachment[1][2]*y+attachment[1][3]*z+attachment[1][4])*rootScale,
      (attachment[2][1]*x+attachment[2][2]*y+attachment[2][3]*z+attachment[2][4])*rootScale,
      (attachment[3][1]*x+attachment[3][2]*y+attachment[3][3]*z+attachment[3][4])*rootScale,
    }
  end
  local baseA,baseB=point(9),point(10)
  check(close((baseA[1]+baseB[1])*.5,attachment[1][4]*rootScale)
      and close((baseA[2]+baseB[2])*.5,attachment[2][4]*rootScale)
      and close((baseA[3]+baseB[3])*.5,attachment[3][4]*rootScale)
      and close(flamePrim.uv[18],1) and close(flamePrim.uv[20],1),
    ("dex %03d flame base is not anchored at the callback's tail matrix"):format(dex))
  check(flamePrim and flamePrim.sampler and flamePrim.sampler.cms == 2
      and flamePrim.sampler.cmt == 2 and flamePrim.sampler.masks == 0
      and flamePrim.sampler.maskt == 0,
    ("dex %03d flame render tile is not clamp/clamp with no mask"):format(dex))

  local frameBytes = {}
  for frame = 0, 7 do
    local pointer = u32(decoded,node.argOffset + 8 + frame * 4)
    local source = decoded:sub(pointer-info.sourceBase+1,pointer-info.sourceBase+0x800)
    local expectedRGBA = assert(Palette.decodeNativeTexture(source,32,64,3,1))
    local entry = model.handlerTextures[frame+1]
    local texture = entry and model.textures[entry.slot+1]
    check(entry and entry.pointer == pointer and entry.format == 3 and entry.size == 1
        and entry.w == 32 and entry.h == 64 and texture and texture.rgba == expectedRGBA,
      ("dex %03d frame %d is not the ROM 32x64 IA8 render image"):format(dex,frame))
    frameBytes[#frameBytes+1] = source
  end
  local signature = table.concat(frameBytes)
  if not sharedFrameBytes then sharedFrameBytes = signature end
  check(signature == sharedFrameBytes,
    ("dex %03d does not use the Charmander family's shared eight images"):format(dex))

  local records = Handlers.compile(model.fx,runtime,info.sourceBase)
  local extension = assert(Handlers.readExtension("DSM4flame-contract"
    .. Handlers.packExtension(records,info.sourceBase,runtime,
      {prims=model.prims,handlerTextures=model.handlerTextures})))
  for frame = 0, 7 do
    local state = select(1,Handlers.runExtension(extension,2,
      {species=dex,materialFrame=frame,textureFrame=7},{}))
    local material = assert(state.materialBySite[flamePrim.callbackOffset])
    check(state.textureBySite[flamePrim.callbackOffset] == flamePrim.fxFrames[frame+1]+1,
      ("dex %03d frame %d texture is not driven by the display counter"):format(dex,frame))
    check(same(material.primitiveColor,{1,1,1,1})
        and same(material.environmentColor,{(180-frame*10)/255,32/255,0,0})
        and same(material.combine,{0xFC309680,0x5F1AFFFF})
        and material.intensity == true,
      ("dex %03d frame %d material does not match func_80070A4C"):format(dex,frame))
  end

  -- Simulate the pre-fix cache layout (regular row-pair vertices and strip
  -- diagonals), then prove Pack.parse upgrades it without changing DSM4/API.
  local saved = {pos=flamePrim.pos,uv=flamePrim.uv,nrm=flamePrim.nrm,
    color=flamePrim.color,skin=flamePrim.skin,idx=flamePrim.idx}
  local oldPos, oldUV, oldNrm, oldColor, oldSkin = {}, {}, {}, {}, {}
  local oldRows = {{200,0,0},{150,512,0},{100,1024,0},{50,1536,192},{0,2048,128}}
  for row, values in ipairs(oldRows) do
    for side = 0, 1 do
      local i = (row-1)*2+side+1
      oldPos[i*3-2],oldPos[i*3-1],oldPos[i*3]=side==0 and -50 or 50,values[1],0
      oldUV[i*2-1],oldUV[i*2]=side,values[2]/1024
      oldNrm[i*3-2],oldNrm[i*3-1],oldNrm[i*3]=0,0,1
      oldColor[i*4-3],oldColor[i*4-2],oldColor[i*4-1],oldColor[i*4]
        =255,255,values[3],255
      oldSkin[i]=saved.skin[1]
    end
  end
  flamePrim.pos,flamePrim.uv,flamePrim.nrm,flamePrim.color,flamePrim.skin
    =oldPos,oldUV,oldNrm,oldColor,oldSkin
  flamePrim.idx={1,2,3,1,3,4,3,4,5,3,5,6,5,6,7,5,7,8,7,8,9,7,9,10}
  local contexts={}
  for i=1,#Build.CONTEXTS do contexts[i]=0xFFFF end
  local oldTextures={}
  for i,texture in ipairs(model.textures) do oldTextures[i]=texture end
  for frame,source in ipairs(frameBytes) do
    local slot=flamePrim.fxFrames[frame]+1
    oldTextures[slot]={w=32,h=32,
      rgba=assert(Palette.decodeNativeTexture(source,32,32,3,2))}
  end
  local cacheFixture={bones=model.bones,prims={flamePrim},textures=oldTextures,
    anims={},auxAnims={},rootScale=model.rootScale,handlerOps={},
    handlerTextures=model.handlerTextures,handlerSourceBase=info.sourceBase,
    handlerFragment=runtime}
  local oldPack=assert(Build.pack(cacheFixture,dex,{},contexts))
  flamePrim.pos,flamePrim.uv,flamePrim.nrm,flamePrim.color,flamePrim.skin,
    flamePrim.idx=saved.pos,saved.uv,saved.nrm,saved.color,saved.skin,saved.idx
  local cached=assert(Pack.parse(oldPack))
  local cachedFlame
  for _,prim in ipairs(cached.prims or {}) do if prim.effect=="fire" then cachedFlame=prim end end
  check(cachedFlame and same(cachedFlame.pos,expectedPos)
      and same(cachedFlame.uv,expectedUV) and same(cachedFlame.color,expectedColor)
      and same(cachedFlame.idx,expectedIndex) and cachedFlame.additive
      and not cachedFlame.cull,
    ("dex %03d legacy cache was not upgraded to the ROM flame object"):format(dex))
  for frame,source in ipairs(frameBytes) do
    local texture=cached.textures[cachedFlame.fxFrames[frame]]
    check(texture and texture.w==32 and texture.h==64
        and texture.rgba==assert(Palette.decodeNativeTexture(source,32,64,3,1)),
      ("dex %03d legacy frame %d was not upgraded from IA16 load to IA8 tile")
        :format(dex,frame-1))
  end
end

print(("Charmander flame contract audit: checks=%d failures=%d")
  :format(checks,#failures))
for _, failure in ipairs(failures) do print("FAIL " .. failure) end
if #failures > 0 then os.exit(1) end
