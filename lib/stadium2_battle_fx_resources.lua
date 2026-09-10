-- Reader for Stadium 2's battle-effect resource archive (main archive group 5).
-- Resource IDs in fragment 79 select archive members; exports inside those
-- members bind the shape IDs referenced by native particle descriptors.
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Phase5Geometry = require(
  "mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")

local Resources = {}

Resources.ROM_START = 0x267D000
Resources.ROM_END = 0x27ED000
Resources.MEMBER_COUNT = 131
Resources.VRAM_BASE = 0x8FF00000

local byte = string.byte

local function u16(data, offset)
  local a,b=byte(data,offset+1,offset+2)
  if not b then return nil end
  return a*256+b
end

local function u32(data, offset)
  return Rom.u32(data,offset)
end

local function sourceArchive(data)
  if type(data)~="string" then return nil,"battle FX resources are not bytes" end
  local offset=#data>=Resources.ROM_END and Resources.ROM_START or 0
  local archive=Rom.archiveAt(data,offset)
  if not archive or archive.count~=Resources.MEMBER_COUNT then
    return nil,"Stadium 2 battle FX resource archive is invalid"
  end
  return archive
end

local function localOffset(module,pointer,length)
  local offset=tonumber(pointer) and pointer-Resources.VRAM_BASE or -1
  length=math.max(1,tonumber(length) or 1)
  if offset<0 or offset+length>#module then return nil end
  return offset
end

function Resources.member(data,id)
  id=math.floor(tonumber(id) or -1)
  local archive,err=sourceArchive(data)
  if not archive then return nil,err end
  if id<0 or id>=archive.count then return nil,"battle FX resource ID out of range" end
  local packed=Rom.recordBytes(data,archive.records[id+1])
  if not packed then return nil,"battle FX resource member is truncated" end
  local module,decompressError=Rom.decompress(packed)
  if not module then return nil,decompressError end
  if module:sub(9,16)~="FRAGMENT" then
    return nil,"battle FX resource member is not a FRAGMENT module"
  end
  return module
end

function Resources.exports(module)
  if type(module)~="string" or module:sub(9,16)~="FRAGMENT" then
    return nil,"invalid battle FX resource module"
  end
  -- FRAGMENT +0x10 stores the file-relative export table offset. Each entry
  -- is kind:u8, pad:u8, symbol:u16, relocated-address:u32 and kind zero ends it.
  local cursor=u32(module,0x10)
  if not cursor or cursor<0x20 or cursor+8>#module then
    return nil,"battle FX export table is outside its module"
  end
  local out={}
  for _=1,4096 do
    local kind=byte(module,cursor+1)
    if not kind then return nil,"battle FX export table is truncated" end
    if kind==0 then return out end
    local symbol,pointer=u16(module,cursor+2),u32(module,cursor+4)
    if not symbol or not pointer then return nil,"battle FX export is truncated" end
    out[#out+1]={kind=kind,symbol=symbol,pointer=pointer,offset=pointer-Resources.VRAM_BASE}
    cursor=cursor+8
  end
  return nil,"battle FX export table did not terminate"
end

function Resources.shape(module,shapeId)
  shapeId=math.floor(tonumber(shapeId) or -1)
  local exports,err=Resources.exports(module)
  if not exports then return nil,err end
  local binding
  for _,entry in ipairs(exports) do
    -- func_84103550 installs every non-zero symbol in DAT_8418CA20. The kind
    -- byte is loader metadata, not a separate runtime namespace.
    if entry.symbol==shapeId then binding=entry break end
  end
  if not binding then return nil,"shape is not exported by this resource" end
  if binding.kind==3 then
    return {id=shapeId,geometryMode=0,export=binding,entries={},
      compiledLayout=true,layoutOffset=binding.offset}
  end
  local shapeOffset=localOffset(module,binding.pointer,8)
  if not shapeOffset then return nil,"exported battle FX shape is outside its module" end
  local geometryMode,count,listPointer=u16(module,shapeOffset),u16(module,shapeOffset+2),u32(module,shapeOffset+4)
  local listOffset=localOffset(module,listPointer,math.max(1,(count or 0)*16))
  if not geometryMode or not count or count>1024 or not listOffset then
    return nil,"exported battle FX shape is malformed"
  end
  local shape={id=shapeId,geometryMode=geometryMode,export=binding,entries={}}
  for index=0,count-1 do
    local offset=listOffset+index*16
    local materialPointer=u32(module,offset)
    local displayListPointer=u32(module,offset+8)
    local materialOffset=localOffset(module,materialPointer,8)
    local displayListOffset=localOffset(module,displayListPointer,8)
    if not materialOffset or not displayListOffset then
      return nil,"battle FX shape entry points outside its module"
    end
    shape.entries[#shape.entries+1]={
      index=index,
      materialPointer=materialPointer,
      materialOffset=materialOffset,
      renderState=u16(module,offset+6),
      displayListPointer=displayListPointer,
      displayListOffset=displayListOffset,
      textures=Phase5Geometry.textureSpecs(module,Resources.VRAM_BASE,materialOffset),
      material=Phase5Geometry.materialSpec(module,Resources.VRAM_BASE,materialOffset,1),
      controller=Phase5Geometry.controllerSpec(module,Resources.VRAM_BASE,materialOffset),
      state=Phase5Geometry.stateSpec(module,Resources.VRAM_BASE,materialOffset),
    }
  end
  return shape
end

-- Reproduce func_80041780 + func_84103550: member zero supplies common
-- symbols, followed by each move-authored resource member in listed order.
-- Later exports overwrite earlier symbols exactly like the game's table.
function Resources.resolve(data,resourceIds)
  local ids={0}
  for _,id in ipairs(resourceIds or {}) do
    id=math.floor(tonumber(id) or -1)
    if id~=0 then ids[#ids+1]=id end
  end
  local result={members={},shapes={}}
  for _,id in ipairs(ids) do
    local module,err=Resources.member(data,id)
    if not module then return nil,("resource %d: %s"):format(id,err) end
    local exports,exportError=Resources.exports(module)
    if not exports then return nil,("resource %d: %s"):format(id,exportError) end
    result.members[id]={id=id,module=module,exports=exports}
    for _,entry in ipairs(exports) do
      result.shapes[entry.symbol]={resourceId=id,module=module,export=entry}
    end
  end
  return result
end

function Resources.shapeFromResolved(resolved,shapeId)
  local binding=resolved and resolved.shapes and resolved.shapes[shapeId]
  if not binding then return nil,"battle FX shape symbol was not loaded" end
  local shape,err=Resources.shape(binding.module,shapeId)
  if shape then
    shape.resourceId=binding.resourceId
    shape._module=binding.module
  end
  return shape,err
end

-- 8415FD8C / 841621A4 load RGBA16 pixels from exports 38/36 at
-- DAT_8418CA20 + 0x98/0x90. These are textures, not shape descriptors.
function Resources.waveGridTexture(resolved,family)
  local symbol=(family==10 or family==11) and 36 or 38
  local binding=resolved and resolved.shapes and resolved.shapes[symbol]
  if not binding then return nil,"wave-grid texture export "..symbol.." was not loaded" end
  local offset=localOffset(binding.module,binding.export.pointer,32*32*2)
  if not offset then return nil,"wave-grid texture export is truncated" end
  local pixels={}
  local function expand(v)return v*8+math.floor(v/4)end
  for i=0,1023 do
    local value=u16(binding.module,offset+i*2)
    pixels[#pixels+1]=string.char(expand(math.floor(value/2048)),
      expand(math.floor(value/64)%32),expand(math.floor(value/2)%32),
      value%2*255)
  end
  return {w=32,h=32,format=0,size=2,rgba=table.concat(pixels),
    resourceId=binding.resourceId,symbol=symbol}
end

-- 84167D2C: beam texture indices select 32x32 I4 images from 8419CA20.
function Resources.beamTexture(resolved,symbol)
  local binding=resolved and resolved.shapes and resolved.shapes[symbol]
  if not binding then return nil,"beam texture export "..tostring(symbol).." was not loaded" end
  local offset=localOffset(binding.module,binding.export.pointer,512)
  if not offset then return nil,"beam texture export is truncated" end
  local pixels={}
  for i=0,511 do
    local byte=binding.module:byte(offset+i+1)
    local hi,lo=math.floor(byte/16)*17,(byte%16)*17
    pixels[#pixels+1]=string.char(hi,hi,hi,255,lo,lo,lo,255)
  end
  return {w=32,h=32,format=4,size=0,rgba=table.concat(pixels),
    resourceId=binding.resourceId,symbol=symbol}
end

function Resources.modelFromShape(shape,name)
  if type(shape)~="table" or type(shape.entries)~="table"
      or type(shape.resourceId)~="number" then
    return nil,"resolved battle FX shape required"
  end
  local module
  -- shapeFromResolved deliberately retains the source module privately so
  -- this conversion never guesses which archive member owns the display list.
  local binding=shape.export
  if binding then module=shape._module end
  if not module then return nil,"battle FX shape source module is unavailable" end
  local function extractModel()
    if shape.compiledLayout then
      Fragment.setBase(Resources.VRAM_BASE)
      return Fragment.extract(module,name or "battle-fx-layout",{
        directLayoutOffset=shape.layoutOffset,bakePhase5Geometry=true})
    end
    local draws={}
    for _,entry in ipairs(shape.entries) do
      local draw={}
      for key,value in pairs(entry) do draw[key]=value end
      draw.geometryMode=shape.geometryMode
      draws[#draws+1]=draw
    end
    return Fragment.extractDisplayLists(module,draws,name,
      Resources.VRAM_BASE)
  end
  -- Resource modules are ROM input. One unsupported graph command should be
  -- reported as a missing drawable rather than terminate a battle or viewer.
  local previousBase=Fragment.getBase()
  local ok,model,err=pcall(extractModel)
  Fragment.setBase(previousBase)
  if not ok then return nil,tostring(model) end
  if not model then return nil,err end
  -- Fragment extraction is internally N64-style and zero based. Public live
  -- models use the same one-based texture/index contract as parsed DSM packs.
  for _,primitive in ipairs(model.prims or {}) do
    primitive.tex=primitive.tex and primitive.tex>=0
      and primitive.tex+1 or 0x10000
    for index,value in ipairs(primitive.idx or {}) do
      primitive.idx[index]=value+1
    end
    for key,value in pairs(primitive.texMap or {}) do
      primitive.texMap[key]=value+1
    end
    for index,value in ipairs(primitive.fxFrames or {}) do
      primitive.fxFrames[index]=value+1
    end
  end
  if type(model.rootScale)=="table" then
    model.rootScaleVector=model.rootScale
    model.rootScale=tonumber(model.rootScale[1]) or 1
  else
    model.rootScale=tonumber(model.rootScale) or 1
  end
  model.staticPose=true
  return model
end

return Resources
