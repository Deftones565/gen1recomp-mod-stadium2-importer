-- Optional reconstruction of Rapidash's disconnected fragment-26 particle
-- callback.  The retail model contains the complete callback argument, quad,
-- and eight I4 images, but its live geometry graph never invokes the node.
-- Keep this augmentation renderer-local so the cached retail model remains
-- untouched and callers can turn the cut effect off without rebuilding it.
local RapidashCut = {
  DESCRIPTOR = 0x81000070,
  TARGET = 0x81005524,
  -- The detached node no longer has owners. These three live flame-chain
  -- anchors correspond to Rapidash's body plume, tail base, and mane crown.
  EMITTER_BONES = {14,19,41},
}

local byte, char, floor = string.byte, string.char, math.floor

local function u32(data, offset)
  local a,b,c,d=byte(data,offset+1,offset+4)
  return d and ((a*256+b)*256+c)*256+d or nil
end

local function i16(data, offset)
  local a,b=byte(data,offset+1,offset+2)
  if not b then return 0 end
  local value=a*256+b
  return value>=0x8000 and value-0x10000 or value
end

local function pointerOffset(extension, pointer, bytes)
  local offset=pointer and pointer-(tonumber(extension.sourceBase) or 0x8FF00000) or -1
  if offset<0 or offset+(bytes or 1)>#extension.fragment then return nil end
  return offset
end

local function callback(extension)
  local data=extension and extension.fragment
  if type(data)~="string" then return nil,"Rapidash source fragment unavailable" end
  for offset=0,#data-12,4 do
    if floor((u32(data,offset) or 0)/0x1000000)==0x08
        and u32(data,offset+4)==RapidashCut.DESCRIPTOR then
      local arg=pointerOffset(extension,u32(data,offset+8),40)
      if arg then return offset,arg end
    end
  end
  return nil,"dormant Rapidash callback unavailable"
end

local function geometry(extension, arg)
  local data=extension.fragment
  local dl=pointerOffset(extension,u32(data,arg+4),16)
  if not dl then return nil,"dormant Rapidash quad unavailable" end
  local command,pointer=u32(data,dl),u32(data,dl+4)
  local count=command and floor(command/0x1000)%256 or 0
  local vtx=pointerOffset(extension,pointer,64)
  if floor((command or 0)/0x1000000)~=0x01 or count~=4 or not vtx then
    return nil,"invalid dormant Rapidash quad"
  end
  local vertices={}
  for i=0,3 do
    local at=vtx+i*16
    vertices[i+1]={x=i16(data,at),y=i16(data,at+2),z=i16(data,at+4),
      s=i16(data,at+8),t=i16(data,at+10)}
  end
  local function tri(word)
    return {floor(floor(word/0x10000)%256/2)+1,
      floor(floor(word/0x100)%256/2)+1,floor(word%256/2)+1}
  end
  local a,b=tri(u32(data,dl+8) or 0),tri(u32(data,dl+12) or 0)
  return {displayListPointer=u32(data,arg+4),vertexPointer=pointer,
    vertices=vertices,indices={a[1],a[2],a[3],b[1],b[2],b[3]}}
end

local function texture(extension, pointer)
  local data=extension.fragment
  local offset=pointerOffset(extension,pointer,32*32/2)
  if not offset then return nil end
  local rgba={}
  for pixel=0,32*32-1 do
    local packed=byte(data,offset+floor(pixel/2)+1)
    local value=(pixel%2==0 and floor(packed/16) or packed%16)*17
    rgba[#rgba+1]=char(value,value,value,255)
  end
  return {w=32,h=32,rgba=table.concat(rgba),callback=true,
    sourcePointer=pointer,format=4,size=0,cutRapidash=true}
end

local function shallow(source)
  local out={}
  for key,value in pairs(source or {}) do out[key]=value end
  return out
end

function RapidashCut.augment(model)
  if type(model)~="table" or tonumber(model.species)~=78
      or type(model.handlers)~="table" then return model end
  if model.cutRapidashEffect then return model end
  local site,arg=callback(model.handlers)
  if not site then return model end
  local quad=geometry(model.handlers,arg)
  if not quad then return model end

  local copy=shallow(model)
  copy.textures={}
  for i,value in ipairs(model.textures or {}) do copy.textures[i]=value end
  local specs={}
  for i=0,7 do
    local pointer=u32(model.handlers.fragment,arg+8+i*4)
    local decoded=texture(model.handlers,pointer)
    if not decoded then return model end
    copy.textures[#copy.textures+1]=decoded
    specs[#specs+1]={slot=#copy.textures-1,pointer=pointer,w=32,h=32,format=4,size=0}
  end
  copy.texCount=#copy.textures

  copy.handlers=shallow(model.handlers)
  copy.handlers.records={}
  for i,value in ipairs(model.handlers.records or {}) do copy.handlers.records[i]=value end
  copy.handlers.records[#copy.handlers.records+1]={
    descriptor=RapidashCut.DESCRIPTOR,target=RapidashCut.TARGET,
    phases={2},family="dynamic-object-renderer",confidence="cut-content",
    commandOffset=site,argOffset=arg,
    argAddress=(tonumber(model.handlers.sourceBase) or 0x8FF00000)+arg,
    bone=RapidashCut.EMITTER_BONES[1],emitterBones=RapidashCut.EMITTER_BONES,
    runtimeDependent=true,cutRapidash=true,
    program={family="dynamic-object-renderer",geometry=quad,textures=specs,
      assets={},complete=true,cutRapidash=true},
  }
  copy.cutRapidashEffect=true
  copy.cutRapidashTextureFirst=#copy.textures-7
  return copy
end

function RapidashCut.release(model)
  if not (model and model.cutRapidashEffect and model.textures) then return end
  for _,slot in ipairs(model.textures) do
    if slot.cutRapidash and slot.image and slot.image.release then
      pcall(slot.image.release,slot.image)
      slot.image=nil
    end
  end
end

return RapidashCut
