local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")

local GLB = {}

GLB.FORMAT = "STADIUM2_GLTF_1"
GLB.MIME = "model/gltf-binary"

local floor, abs, sqrt = math.floor, math.abs, math.sqrt
local sin, cos, pi = math.sin, math.cos, math.pi
local char, concat = string.char, table.concat
local bitlib = bit or require("bit")
local band, bxor, rshift = bitlib.band, bitlib.bxor, bitlib.rshift

local ARRAY = {}
local function array(values)
  return setmetatable(values or {}, ARRAY)
end

local function jsonString(value)
  value=tostring(value)
  local out={'"'}
  local replacements = { [34]='\\"', [92]='\\\\', [8]='\\b',
    [12]='\\f', [10]='\\n', [13]='\\r', [9]='\\t' }
  for i=1,#value do
    local byte=value:byte(i)
    out[#out+1]=replacements[byte]
      or ((byte<32 or byte>=127) and ("\\u%04x"):format(byte))
      or char(byte)
  end
  out[#out+1]='"'
  return concat(out)
end

local function jsonEncode(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then return "null" end
    return ("%.9g"):format(value)
  end
  if kind == "string" then return jsonString(value) end
  if kind ~= "table" then error("unsupported JSON value: " .. kind, 0) end
  local out = {}
  if getmetatable(value) == ARRAY then
    for i = 1, #value do out[i] = jsonEncode(value[i]) end
    return "[" .. concat(out, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" then error("JSON object key must be a string", 0) end
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for i, key in ipairs(keys) do
    out[i] = jsonString(key) .. ":" .. jsonEncode(value[key])
  end
  return "{" .. concat(out, ",") .. "}"
end

local function u16le(v)
  v = floor(tonumber(v) or 0) % 65536
  return char(v % 256, floor(v / 256))
end

local function u32le(v)
  v = floor(tonumber(v) or 0) % 4294967296
  return char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256,
    floor(v / 16777216) % 256)
end

local function u32be(v)
  v = floor(tonumber(v) or 0) % 4294967296
  return char(floor(v / 16777216) % 256, floor(v / 65536) % 256,
    floor(v / 256) % 256, v % 256)
end

local function f32le(v)
  return Build.f32(tonumber(v) or 0)
end

local crcTable = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do
    if band(c, 1) ~= 0 then c = bxor(0xEDB88320, rshift(c, 1))
    else c = rshift(c, 1) end
  end
  crcTable[n] = c
end

local function crc32(value)
  local crc = 0xFFFFFFFF
  for i = 1, #value do
    crc = bxor(crcTable[band(bxor(crc, value:byte(i)), 0xFF)], rshift(crc, 8))
  end
  return band(bxor(crc, 0xFFFFFFFF), 0xFFFFFFFF)
end

local function pngChunk(kind, body)
  local payload = kind .. body
  return u32be(#body) .. payload .. u32be(crc32(payload))
end

local function adler32(value)
  local a, b = 1, 0
  for i = 1, #value do
    a = (a + value:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

local function zlibStored(value)
  local out, at, remaining = { char(0x78, 0x01) }, 1, #value
  while remaining > 0 do
    local n = math.min(65535, remaining)
    local final = n == remaining and 1 or 0
    out[#out + 1] = char(final) .. u16le(n) .. u16le(0xFFFF - n)
      .. value:sub(at, at + n - 1)
    at, remaining = at + n, remaining - n
  end
  out[#out + 1] = u32be(adler32(value))
  return concat(out)
end

function GLB.png(texture)
  if type(texture) ~= "table" then return nil, "texture required" end
  local width, height = floor(tonumber(texture.w) or 0), floor(tonumber(texture.h) or 0)
  local rgba = texture.rgba
  if width < 1 or height < 1 or type(rgba) ~= "string"
      or #rgba ~= width * height * 4 then
    return nil, "invalid RGBA texture"
  end
  local rows = {}
  local stride = width * 4
  for y = 0, height - 1 do
    rows[#rows + 1] = "\0" .. rgba:sub(y * stride + 1, (y + 1) * stride)
  end
  local ihdr = u32be(width) .. u32be(height) .. char(8, 6, 0, 0, 0)
  return "\137PNG\r\n\26\n" .. pngChunk("IHDR", ihdr)
    .. pngChunk("IDAT", zlibStored(concat(rows))) .. pngChunk("IEND", "")
end

local function normalize3(x, y, z)
  local length = sqrt(x*x + y*y + z*z)
  if length <= 1e-12 then return 0, 1, 0 end
  return x/length, y/length, z/length
end

local function transformPoint(m, x, y, z)
  return m[1][1]*x+m[1][2]*y+m[1][3]*z+m[1][4],
    m[2][1]*x+m[2][2]*y+m[2][3]*z+m[2][4],
    m[3][1]*x+m[3][2]*y+m[3][3]*z+m[3][4]
end

local function transformDirection(m, x, y, z)
  return normalize3(m[1][1]*x+m[1][2]*y+m[1][3]*z,
    m[2][1]*x+m[2][2]*y+m[2][3]*z,
    m[3][1]*x+m[3][2]*y+m[3][3]*z)
end

local function inverseAffine(m)
  local a,b,c,d,e,f,g,h,i = m[1][1],m[1][2],m[1][3],
    m[2][1],m[2][2],m[2][3],m[3][1],m[3][2],m[3][3]
  local det = a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
  if abs(det) < 1e-12 then return nil end
  local q = 1/det
  local r = {
    {(e*i-f*h)*q,(c*h-b*i)*q,(b*f-c*e)*q,0},
    {(f*g-d*i)*q,(a*i-c*g)*q,(c*d-a*f)*q,0},
    {(d*h-e*g)*q,(b*g-a*h)*q,(a*e-b*d)*q,0},
    {0,0,0,1},
  }
  local x,y,z=m[1][4],m[2][4],m[3][4]
  r[1][4]=-(r[1][1]*x+r[1][2]*y+r[1][3]*z)
  r[2][4]=-(r[2][1]*x+r[2][2]*y+r[2][3]*z)
  r[3][4]=-(r[3][1]*x+r[3][2]*y+r[3][3]*z)
  return r
end

local function matrixBytesColumnMajor(m)
  local out = {}
  for column = 1, 4 do
    for row = 1, 4 do out[#out + 1] = f32le(m[row][column]) end
  end
  return concat(out)
end

local function identity4()
  return {{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}}
end

local function quaternion(rotation)
  if rotation[4]~=nil then
    local x,y,z,w=tonumber(rotation[1]) or 0,tonumber(rotation[2]) or 0,
      tonumber(rotation[3]) or 0,tonumber(rotation[4]) or 1
    local length=sqrt(x*x+y*y+z*z+w*w)
    if length<=1e-12 then return {0,0,0,1} end
    return {x/length,y/length,z/length,w/length}
  end
  local hx=(tonumber(rotation[1]) or 0)/32768*pi*0.5
  local hy=(tonumber(rotation[2]) or 0)/32768*pi*0.5
  local hz=(tonumber(rotation[3]) or 0)/32768*pi*0.5
  local sx,cx,sy,cy,sz,cz=sin(hx),cos(hx),sin(hy),cos(hy),sin(hz),cos(hz)
  local x=sx*cy*cz-cx*sy*sz
  local y=cx*sy*cz+sx*cy*sz
  local z=cx*cy*sz-sx*sy*cz
  local w=cx*cy*cz+sx*sy*sz
  local length=sqrt(x*x+y*y+z*z+w*w)
  if length <= 1e-12 then return {0,0,0,1} end
  return {x/length,y/length,z/length,w/length}
end

local function trackComponent(track, component, frame, fallback)
  if type(track) ~= "table" then return fallback end
  local value=track[component]
  if type(value)=="table" then return value[math.min(#value,frame+1)] or fallback end
  if value==nil then return fallback end
  return value
end

local function poseTRS(bone, track, frame)
  return {
    trackComponent(track and track.t,1,frame,bone.t[1]),
    trackComponent(track and track.t,2,frame,bone.t[2]),
    trackComponent(track and track.t,3,frame,bone.t[3]),
  },{
    trackComponent(track and track.r,1,frame,bone.r[1]),
    trackComponent(track and track.r,2,frame,bone.r[2]),
    trackComponent(track and track.r,3,frame,bone.r[3]),
  },{
    trackComponent(track and track.s,1,frame,bone.s[1]),
    trackComponent(track and track.s,2,frame,bone.s[2]),
    trackComponent(track and track.s,3,frame,bone.s[3]),
  }
end

local function safeScalars(value, depth)
  if depth > 8 then return nil end
  local kind=type(value)
  if kind=="string" then
    if #value > 512 then return nil end
    return value
  end
  if kind=="number" or kind=="boolean" then return value end
  if kind~="table" then return nil end
  local isList=#value>0
  local out=isList and array() or {}
  if isList then
    for i=1,#value do
      local item=safeScalars(value[i],depth+1)
      if item~=nil then out[#out+1]=item end
    end
  else
    for key,item in pairs(value) do
      local outputKey=type(key)=="string" and key or type(key)=="number" and tostring(key) or nil
      if outputKey and outputKey~="fragment" and outputKey~="bytes"
          and outputKey~="commands" and outputKey~="image" then
        local clean=safeScalars(item,depth+1)
        if clean~=nil then out[outputKey]=clean end
      end
    end
  end
  return out
end

local function stadiumMetadata(model, primitiveIndex, prim)
  local wrapS,wrapT=Sampler.wrap(prim.sampler)
  local metadata={
    format=GLB.FORMAT,
    primitive=primitiveIndex,
    sourceTexture=prim.tex,
    cull=prim.cull==true,
    additive=prim.additive==true,
    lighting=prim.lighting~=false,
    decal=prim.decal==true,
    sourceTextureMissing=prim.sourceTextureMissing==true,
    geometryMode=prim.geometryMode or 0,
    wrapS=wrapS,wrapT=wrapT,
    textureScale=array({prim.textureScale and prim.textureScale[1] or 1,
      prim.textureScale and prim.textureScale[2] or 1}),
  }
  if prim.effect then metadata.effect=prim.effect end
  if prim.callbackOffset then metadata.callbackOffset=prim.callbackOffset end
  if prim.materialOffset then metadata.materialOffset=prim.materialOffset end
  if prim.texAnim and prim.texAnim>=0 then metadata.textureAnimationChannel=prim.texAnim end
  if prim.texMap then metadata.textureMap=safeScalars(prim.texMap,0) end
  if prim.fxFrames then metadata.effectFrames=safeScalars(prim.fxFrames,0) end
  if prim.sampler then metadata.sampler=safeScalars(prim.sampler,0) end
  if prim.material then metadata.material=safeScalars(prim.material,0) end
  return metadata
end

local function newDocument()
  local document={
    asset={version="2.0",generator="STADIUM2_IMPORTER "..GLB.FORMAT},
    scene=0,
    scenes=array(),nodes=array(),meshes=array(),skins=array(),animations=array(),
    accessors=array(),bufferViews=array(),buffers=array(),materials=array(),
    images=array(),textures=array(),samplers=array(),
  }
  local binary={parts={},length=0}
  local function addView(bytes,target,alignment)
    alignment=alignment or 4
    local padding=(alignment-binary.length%alignment)%alignment
    if padding>0 then
      binary.parts[#binary.parts+1]=string.rep("\0",padding)
      binary.length=binary.length+padding
    end
    local view={buffer=0,byteOffset=binary.length,byteLength=#bytes}
    if target then view.target=target end
    document.bufferViews[#document.bufferViews+1]=view
    binary.parts[#binary.parts+1]=bytes
    binary.length=binary.length+#bytes
    return #document.bufferViews-1
  end
  local function addAccessor(bytes,componentType,count,valueType,options)
    options=options or {}
    local accessor={bufferView=addView(bytes,options.target,options.alignment),
      byteOffset=0,componentType=componentType,count=count,type=valueType}
    if options.normalized then accessor.normalized=true end
    if options.min then accessor.min=array(options.min) end
    if options.max then accessor.max=array(options.max) end
    document.accessors[#document.accessors+1]=accessor
    return #document.accessors-1
  end
  return document,binary,addView,addAccessor
end

local function colorFactor(material)
  local color=material and material.primitiveColor
  if type(color)~="table" then return {1,1,1,1} end
  return {tonumber(color[1]) or 1,tonumber(color[2]) or 1,
    tonumber(color[3]) or 1,tonumber(color[4]) or 1}
end

local function hasAlpha(texture)
  if not (texture and type(texture.rgba)=="string") then return false end
  for i=4,#texture.rgba,4 do if texture.rgba:byte(i)<255 then return true end end
  return false
end

local function wrapCode(value)
  if value=="repeat" then return 10497 end
  if value=="mirroredrepeat" then return 33648 end
  return 33071
end

function GLB.encode(model,options)
  if type(model)~="table" or type(model.prims)~="table" then
    return nil,"parsed Stadium model required"
  end
  options=type(options)=="table" and options or {}
  local document,binary,addView,addAccessor=newDocument()
  document.asset.extras={stadium2={format=GLB.FORMAT,species=model.species,
    variant=options.variant or model.variant or "normal",fps=30,
    rootScale=model.rootScale or 1,height=model.height,floor=model.floor,
    radius=model.radius,staticPose=model.staticPose==true,
    contexts=safeScalars(model.context or {},0),
    moveAnimations=safeScalars(model.moveAnim or {},0),
    moveAuxiliary=safeScalars(model.moveAux or {},0),
    auxiliaryAnimations=safeScalars(model.auxAnims or {},0)}}
  if type(model.bytes)=="string" then
    document.asset.extras.stadium2.sourcePack={
      bufferView=addView(model.bytes,nil,4),
      mimeType="application/x-stadium2-dsm4",
      byteLength=#model.bytes,
    }
  end

  local bindMatrices,pivotMatrices=Build.bindMatrices(model.bones or {})
  local inverseBytes,localBindFallback={},{}
  for i,matrix in ipairs(bindMatrices) do
    local inverse=inverseAffine({matrix[1],matrix[2],matrix[3],{0,0,0,1}})
    -- Stadium uses zero-scale joints as visibility switches. Such a bind
    -- matrix has no inverse. Rigid vertices owned by that joint can remain in
    -- joint-local coordinates with an identity inverse bind; the joint's
    -- animated world transform then produces the same final position.
    if not inverse then
      inverse=identity4()
      localBindFallback[i]=true
    end
    inverseBytes[#inverseBytes+1]=matrixBytesColumnMajor(inverse)
  end
  local inverseAccessor=addAccessor(concat(inverseBytes),5126,#bindMatrices,"MAT4")

  local rootNode={name=(options.name or ("stadium2_%03d"):format(model.species or 0)),
    scale=array({model.rootScale or 1,model.rootScale or 1,model.rootScale or 1}),
    children=array()}
  document.nodes[#document.nodes+1]=rootNode
  local rootIndex=0
  local jointIndices=array()
  for i,bone in ipairs(model.bones or {}) do
    local node={name=("bone_%03d"):format(i-1),translation=array({bone.t[1],bone.t[2],bone.t[3]}),
      rotation=array(quaternion(bone.r)),scale=array({bone.s[1],bone.s[2],bone.s[3]}),
      extras={stadium2={bone=i-1,parent=bone.parent}}}
    document.nodes[#document.nodes+1]=node
    jointIndices[#jointIndices+1]=#document.nodes-1
  end
  for i,bone in ipairs(model.bones or {}) do
    local node=document.nodes[jointIndices[i]+1]
    if bone.parent>=0 and jointIndices[bone.parent+1] then
      local parent=document.nodes[jointIndices[bone.parent+1]+1]
      parent.children=parent.children or array()
      parent.children[#parent.children+1]=jointIndices[i]
    else rootNode.children[#rootNode.children+1]=jointIndices[i] end
  end

  local samplerCache,textureCache,imageCache={},{},{}
  local function imageFor(textureIndex)
    if imageCache[textureIndex]~=nil then return imageCache[textureIndex] end
    local source=model.textures and model.textures[textureIndex]
    if not source then return nil end
    local png,pngErr=GLB.png(source)
    if not png then error(pngErr,0) end
    document.images[#document.images+1]={name=("texture_%03d"):format(textureIndex-1),
      bufferView=addView(png,nil,4),mimeType="image/png",
      extras={stadium2={sourceIndex=textureIndex}}}
    imageCache[textureIndex]=#document.images-1
    return imageCache[textureIndex]
  end
  local function textureFor(textureIndex,wrapS,wrapT)
    local key=table.concat({textureIndex,wrapS,wrapT},":")
    if textureCache[key] then return textureCache[key] end
    local imageIndex=imageFor(textureIndex)
    if imageIndex==nil then return nil end
    local samplerKey=wrapS..":"..wrapT
    local samplerIndex=samplerCache[samplerKey]
    if samplerIndex==nil then
      document.samplers[#document.samplers+1]={magFilter=9728,minFilter=9728,
        wrapS=wrapCode(wrapS),wrapT=wrapCode(wrapT)}
      samplerIndex=#document.samplers-1
      samplerCache[samplerKey]=samplerIndex
    end
    document.textures[#document.textures+1]={source=imageIndex,sampler=samplerIndex,
      extras={stadium2={sourceIndex=textureIndex}}}
    local result=#document.textures-1
    textureCache[key]=result
    return result
  end

  local textureTable=array()
  for textureIndex=1,#(model.textures or {}) do
    textureTable[#textureTable+1]={sourceIndex=textureIndex,
      image=imageFor(textureIndex),texture=textureFor(textureIndex,"clamp","clamp")}
  end
  document.asset.extras.stadium2.textureTable=textureTable

  local primitives=array()
  for primitiveIndex,prim in ipairs(model.prims) do
    local positions,normals,uvs,colors,joints,weights={},{},{},{},{},{}
    local minv={math.huge,math.huge,math.huge}
    local maxv={-math.huge,-math.huge,-math.huge}
    local us,vs=Sampler.uvScale(prim.sampler,prim.textureScale)
    local material=prim.material
    for vertex=1,prim.nverts do
      local boneIndex=(prim.skin[vertex] or 0)+1
      local bind=bindMatrices[boneIndex]
      local pivot=pivotMatrices[boneIndex]
      if not (bind and pivot) then return nil,("primitive %d has invalid bone %d")
        :format(primitiveIndex, boneIndex-1) end
      local rawX,rawY,rawZ=prim.pos[vertex*3-2],prim.pos[vertex*3-1],prim.pos[vertex*3]
      local x,y,z
      if localBindFallback[boneIndex] then x,y,z=rawX,rawY,rawZ
      else x,y,z=transformPoint(bind,rawX,rawY,rawZ) end
      positions[#positions+1]=f32le(x)..f32le(y)..f32le(z)
      minv[1],minv[2],minv[3]=math.min(minv[1],x),math.min(minv[2],y),math.min(minv[3],z)
      maxv[1],maxv[2],maxv[3]=math.max(maxv[1],x),math.max(maxv[2],y),math.max(maxv[3],z)
      local nx,ny,nz
      if localBindFallback[boneIndex] then
        nx,ny,nz=normalize3(prim.nrm[vertex*3-2] or 0,
          prim.nrm[vertex*3-1] or 1,prim.nrm[vertex*3] or 0)
      else
        nx,ny,nz=transformDirection(pivot,prim.nrm[vertex*3-2] or 0,
          prim.nrm[vertex*3-1] or 1,prim.nrm[vertex*3] or 0)
      end
      normals[#normals+1]=f32le(nx)..f32le(ny)..f32le(nz)
      uvs[#uvs+1]=f32le((prim.uv[vertex*2-1] or 0)*us)
        ..f32le((prim.uv[vertex*2] or 0)*vs)
      if prim.vertexSemantics=="color" then
        colors[#colors+1]=char(prim.color[vertex*4-3] or 255,prim.color[vertex*4-2] or 255,
          prim.color[vertex*4-1] or 255,prim.color[vertex*4] or 255)
      else colors[#colors+1]="\255\255\255\255" end
      local joint=boneIndex-1
      joints[#joints+1]=u16le(joint).."\0\0\0\0\0\0"
      weights[#weights+1]="\255\0\0\0"
    end
    local indices={}
    for i=1,prim.nidx do indices[#indices+1]=u16le((prim.idx[i] or 1)-1) end
    local attributes={
      POSITION=addAccessor(concat(positions),5126,prim.nverts,"VEC3",
        {target=34962,min=minv,max=maxv}),
      NORMAL=addAccessor(concat(normals),5126,prim.nverts,"VEC3",{target=34962}),
      TEXCOORD_0=addAccessor(concat(uvs),5126,prim.nverts,"VEC2",{target=34962}),
      COLOR_0=addAccessor(concat(colors),5121,prim.nverts,"VEC4",
        {target=34962,normalized=true,alignment=1}),
      JOINTS_0=addAccessor(concat(joints),5123,prim.nverts,"VEC4",
        {target=34962,alignment=2}),
      WEIGHTS_0=addAccessor(concat(weights),5121,prim.nverts,"VEC4",
        {target=34962,normalized=true,alignment=1}),
    }
    local wrapS,wrapT=Sampler.wrap(prim.sampler)
    local textureIndex=textureFor(prim.tex,wrapS,wrapT)
    local base=colorFactor(material)
    local sourceTexture=model.textures and model.textures[prim.tex]
    local pbr={baseColorFactor=array(base),metallicFactor=0,roughnessFactor=1}
    if textureIndex~=nil then pbr.baseColorTexture={index=textureIndex} end
    local gltfMaterial={name=("material_%03d"):format(primitiveIndex-1),
      pbrMetallicRoughness=pbr,doubleSided=not prim.cull,
      extras={stadium2=stadiumMetadata(model,primitiveIndex,prim)}}
    if prim.additive then gltfMaterial.alphaMode="BLEND"
    elseif hasAlpha(sourceTexture) or prim.decal then
      gltfMaterial.alphaMode="MASK";gltfMaterial.alphaCutoff=0.01
    else gltfMaterial.alphaMode="OPAQUE" end
    if prim.lighting==false then
      gltfMaterial.extensions={KHR_materials_unlit={}}
      document.extensionsUsed=document.extensionsUsed or array()
      if #document.extensionsUsed==0 then document.extensionsUsed[1]="KHR_materials_unlit" end
    end
    document.materials[#document.materials+1]=gltfMaterial
    primitives[#primitives+1]={attributes=attributes,
      indices=addAccessor(concat(indices),5123,prim.nidx,"SCALAR",{target=34963,alignment=2}),
      material=#document.materials-1,mode=4,
      extras={stadium2=stadiumMetadata(model,primitiveIndex,prim)}}
  end
  document.meshes[1]={name=rootNode.name.."_mesh",primitives=primitives}
  local meshNode={name=rootNode.name.."_skinned",mesh=0,skin=0}
  document.nodes[#document.nodes+1]=meshNode
  rootNode.children[#rootNode.children+1]=#document.nodes-1
  document.skins[1]={name=rootNode.name.."_skin",joints=jointIndices,
    inverseBindMatrices=inverseAccessor}
  local fallbackJoints=array()
  for boneIndex in pairs(localBindFallback) do fallbackJoints[#fallbackJoints+1]=boneIndex-1 end
  table.sort(fallbackJoints)
  if #fallbackJoints>0 then
    document.skins[1].extras={stadium2={localBindFallbackJoints=fallbackJoints}}
  end
  if #jointIndices>0 then document.skins[1].skeleton=jointIndices[1] end
  document.scenes[1]={name="Scene",nodes=array({rootIndex})}

  for animationIndex,animation in ipairs(model.anims or {}) do
    local channels,samplers=array(),array()
    local frames=math.max(1,tonumber(animation.frames) or 1)
    local times={}
    for frame=0,frames-1 do times[#times+1]=f32le(frame/30) end
    local timeAccessor=addAccessor(concat(times),5126,frames,"SCALAR",
      {min={0},max={(frames-1)/30}})
    local animatedBones={}
    for boneIndex in pairs(animation.tracks or {}) do animatedBones[#animatedBones+1]=boneIndex end
    table.sort(animatedBones)
    for _,boneIndex in ipairs(animatedBones) do
      local track=animation.tracks[boneIndex]
      local bone=model.bones[boneIndex]
      local nodeIndex=jointIndices[boneIndex]
      if bone and nodeIndex then
        local translations,rotations,scales={},{},{}
        local previous
        for frame=0,frames-1 do
          local t,r,s=poseTRS(bone,track,frame)
          translations[#translations+1]=f32le(t[1])..f32le(t[2])..f32le(t[3])
          local q=quaternion(r)
          if previous and previous[1]*q[1]+previous[2]*q[2]+previous[3]*q[3]+previous[4]*q[4]<0 then
            q={-q[1],-q[2],-q[3],-q[4]}
          end
          previous=q
          rotations[#rotations+1]=f32le(q[1])..f32le(q[2])..f32le(q[3])..f32le(q[4])
          scales[#scales+1]=f32le(s[1])..f32le(s[2])..f32le(s[3])
        end
        local outputs={
          {"translation",addAccessor(concat(translations),5126,frames,"VEC3")},
          {"rotation",addAccessor(concat(rotations),5126,frames,"VEC4")},
          {"scale",addAccessor(concat(scales),5126,frames,"VEC3")},
        }
        for _,output in ipairs(outputs) do
          samplers[#samplers+1]={input=timeAccessor,output=output[2],interpolation="LINEAR"}
          channels[#channels+1]={sampler=#samplers-1,target={node=nodeIndex,path=output[1]}}
        end
      end
    end
    if #channels>0 then
      document.animations[#document.animations+1]={
        name=animation.name~="" and animation.name or ("animation_%03d"):format(animationIndex-1),
        channels=channels,samplers=samplers,
        extras={stadium2={sourceIndex=animationIndex-1,sourceFPS=30,
          frameCount=frames,loopStart=animation.loopStart or 0,auxiliary=animation.aux}}}
    end
  end

  local handlerRecords=array()
  for _,record in ipairs(model.handlers and model.handlers.records or {}) do
    handlerRecords[#handlerRecords+1]=safeScalars(record,0)
  end
  if #handlerRecords>0 then document.asset.extras.stadium2.handlers=handlerRecords end
  local binaryBytes=concat(binary.parts)
  document.buffers[1]={byteLength=#binaryBytes}
  local json=jsonEncode(document)
  local jsonPadding=(4-#json%4)%4
  json=json..string.rep(" ",jsonPadding)
  local binaryPadding=(4-#binaryBytes%4)%4
  binaryBytes=binaryBytes..string.rep("\0",binaryPadding)
  local total=12+8+#json+8+#binaryBytes
  local bytes="glTF"..u32le(2)..u32le(total)
    ..u32le(#json).."JSON"..json
    ..u32le(#binaryBytes).."BIN\0"..binaryBytes
  return bytes,{species=model.species,variant=options.variant or model.variant or "normal",
    primitives=#model.prims,textures=#(model.textures or {}),bones=#(model.bones or {}),
    animations=#(model.anims or {}),bytes=#bytes,format=GLB.FORMAT}
end

GLB.array=array
GLB.jsonEncode=jsonEncode

return GLB
