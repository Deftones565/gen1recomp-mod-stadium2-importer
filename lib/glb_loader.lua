local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")

local Loader={}
Loader.FORMAT="STADIUM2_GLTF_1"

local floor,sqrt=math.floor,math.sqrt
local unpack=table.unpack or unpack

local function u16(s,p)
  local a,b=s:byte(p,p+1);return a+b*256
end
local function i16(s,p)
  local v=u16(s,p);return v>=32768 and v-65536 or v
end
local function u32(s,p)
  local a,b,c,d=s:byte(p,p+3);return a+b*256+c*65536+d*16777216
end
local function i32(s,p)
  local v=u32(s,p);return v>=2147483648 and v-4294967296 or v
end
local function f32(s,p)
  local b1,b2,b3,b4=s:byte(p,p+3)
  local sign=1
  if b4>=128 then sign,b4=-1,b4-128 end
  local exponent=b4*2+floor(b3/128)
  local mantissa=(b3%128)*65536+b2*256+b1
  if exponent==255 then return mantissa==0 and sign*math.huge or 0/0 end
  if exponent==0 then return sign*mantissa*2^-149 end
  return sign*(1+mantissa/8388608)*2^(exponent-127)
end

local function utf8(codepoint)
  if codepoint<=0x7F then return string.char(codepoint) end
  if codepoint<=0x7FF then
    return string.char(0xC0+floor(codepoint/64),0x80+codepoint%64)
  end
  if codepoint<=0xFFFF then
    return string.char(0xE0+floor(codepoint/4096),
      0x80+floor(codepoint/64)%64,0x80+codepoint%64)
  end
  return string.char(0xF0+floor(codepoint/262144),
    0x80+floor(codepoint/4096)%64,0x80+floor(codepoint/64)%64,0x80+codepoint%64)
end

local function decodeJSON(source)
  local at,length=1,#source
  local function whitespace()
    while at<=length and source:sub(at,at):match("%s") do at=at+1 end
  end
  local parse
  local function stringValue()
    at=at+1
    local out={}
    while at<=length do
      local c=source:sub(at,at);at=at+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        local escape=source:sub(at,at);at=at+1
        local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if escape=='u' then
          local code=tonumber(source:sub(at,at+3),16)
          if not code then error("invalid JSON unicode escape",0) end
          at=at+4
          if code>=0xD800 and code<=0xDBFF and source:sub(at,at+1)=='\\u' then
            local low=tonumber(source:sub(at+2,at+5),16)
            if low and low>=0xDC00 and low<=0xDFFF then
              code=0x10000+(code-0xD800)*0x400+(low-0xDC00);at=at+6
            end
          end
          out[#out+1]=utf8(code)
        else
          if not map[escape] then error("invalid JSON escape",0) end
          out[#out+1]=map[escape]
        end
      else out[#out+1]=c end
    end
    error("unterminated JSON string",0)
  end
  local function numberValue()
    local start=at
    while at<=length and source:sub(at,at):match("[%d%+%-%.eE]") do at=at+1 end
    local value=tonumber(source:sub(start,at-1))
    if value==nil then error("invalid JSON number",0) end
    return value
  end
  parse=function()
    whitespace()
    local c=source:sub(at,at)
    if c=='"' then return stringValue() end
    if c=='{' then
      at=at+1;whitespace();local object={}
      if source:sub(at,at)=='}' then at=at+1;return object end
      while true do
        whitespace();if source:sub(at,at)~='"' then error("JSON object key expected",0) end
        local key=stringValue();whitespace()
        if source:sub(at,at)~=':' then error("JSON colon expected",0) end
        at=at+1;object[key]=parse();whitespace();c=source:sub(at,at);at=at+1
        if c=='}' then return object end
        if c~=',' then error("JSON object separator expected",0) end
      end
    end
    if c=='[' then
      at=at+1;whitespace();local values={}
      if source:sub(at,at)==']' then at=at+1;return values end
      while true do
        values[#values+1]=parse();whitespace();c=source:sub(at,at);at=at+1
        if c==']' then return values end
        if c~=',' then error("JSON array separator expected",0) end
      end
    end
    if source:sub(at,at+3)=="true" then at=at+4;return true end
    if source:sub(at,at+4)=="false" then at=at+5;return false end
    if source:sub(at,at+3)=="null" then at=at+4;return nil end
    if c:match("[%d%-]") then return numberValue() end
    error("invalid JSON value at byte "..at,0)
  end
  local value=parse();whitespace()
  if at<=length then error("trailing JSON data",0) end
  return value
end

local COMPONENTS={SCALAR=1,VEC2=2,VEC3=3,VEC4=4,MAT2=4,MAT3=9,MAT4=16}
local SIZES={[5120]=1,[5121]=1,[5122]=2,[5123]=2,[5125]=4,[5126]=4}
local function componentValue(bytes,position,kind,normalized)
  local value
  if kind==5120 then value=bytes:byte(position);if value>=128 then value=value-256 end
  elseif kind==5121 then value=bytes:byte(position)
  elseif kind==5122 then value=i16(bytes,position)
  elseif kind==5123 then value=u16(bytes,position)
  elseif kind==5125 then value=u32(bytes,position)
  elseif kind==5126 then return f32(bytes,position)
  else error("unsupported glTF component type "..tostring(kind),0) end
  if normalized then
    if kind==5120 then return math.max(-1,value/127) end
    if kind==5121 then return value/255 end
    if kind==5122 then return math.max(-1,value/32767) end
    if kind==5123 then return value/65535 end
    if kind==5125 then return value/4294967295 end
  end
  return value
end

local function parseContainer(bytes)
  if type(bytes)~="string" or bytes:sub(1,4)~="glTF" then return nil,"not a GLB file" end
  if #bytes<20 or u32(bytes,5)~=2 then return nil,"unsupported GLB version" end
  if u32(bytes,9)~=#bytes then return nil,"GLB length mismatch" end
  local at,json,binary=13
  while at<=#bytes-7 do
    local size,kind=u32(bytes,at),bytes:sub(at+4,at+7)
    local body=bytes:sub(at+8,at+7+size)
    if #body~=size then return nil,"truncated GLB chunk" end
    if kind=="JSON" then json=body:gsub("%s+$","")
    elseif kind=="BIN\0" then binary=body end
    at=at+8+size
  end
  if not json then return nil,"GLB has no JSON chunk" end
  local ok,document=pcall(decodeJSON,json)
  if not ok then return nil,"invalid GLB JSON: "..tostring(document) end
  return {document=document,binary=binary or "",bytes=bytes}
end

local function viewBytes(container,index)
  local view=container.document.bufferViews and container.document.bufferViews[index+1]
  if not view then return nil,"missing bufferView "..tostring(index) end
  if (view.buffer or 0)~=0 then return nil,"external GLB buffers are unsupported" end
  local start=(view.byteOffset or 0)+1
  return container.binary:sub(start,start+(view.byteLength or 0)-1),view
end

local function accessorValues(container,index)
  local accessor=container.document.accessors and container.document.accessors[index+1]
  if not accessor then return nil,"missing accessor "..tostring(index) end
  local components=COMPONENTS[accessor.type]
  local size=SIZES[accessor.componentType]
  if not (components and size) then return nil,"unsupported accessor layout" end
  local bytes,view=viewBytes(container,accessor.bufferView)
  if not bytes then return nil,view end
  local stride=view.byteStride or components*size
  local base=(accessor.byteOffset or 0)+1
  local values={}
  for element=0,(accessor.count or 0)-1 do
    local row={}
    local position=base+element*stride
    for component=1,components do
      row[component]=componentValue(bytes,position+(component-1)*size,
        accessor.componentType,accessor.normalized==true)
    end
    values[element+1]=components==1 and row[1] or row
  end
  return values
end

local function decodeImage(encoded,mime,index,options)
  if type(options.imageDecoder)=="function" then
    return options.imageDecoder(encoded,mime,index)
  end
  if not (love and love.data and love.data.newByteData and love.image
      and love.image.newImageData) then return nil,"LÖVE encoded image decoder unavailable" end
  local ok,result=pcall(function()
    local data=love.data.newByteData(encoded)
    local imageData=love.image.newImageData(data)
    local width,height=imageData:getDimensions()
    local rgba=imageData:getString()
    if imageData.release then imageData:release() end
    if data.release then data:release() end
    return {w=width,h=height,rgba=rgba}
  end)
  if not ok then return nil,("image %d (%s) failed: %s"):format(index,mime,tostring(result)) end
  return result
end

local function matrixFromAccessor(values)
  local matrices={}
  for index,value in ipairs(values or {}) do
    local matrix={{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}}
    for column=1,4 do for row=1,4 do matrix[row][column]=value[(column-1)*4+row] end end
    matrices[index]=matrix
  end
  return matrices
end

local function identity4()
  return {{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}}
end

local normalizeQuaternion

local function multiply4(a,b)
  local out={{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}}
  for row=1,4 do for column=1,4 do
    for k=1,4 do out[row][column]=out[row][column]+a[row][k]*b[k][column] end
  end end
  return out
end

local function nodeMatrix(node)
  if type(node.matrix)=="table" and #node.matrix>=16 then
    local matrix={{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}}
    for column=1,4 do for row=1,4 do
      matrix[row][column]=node.matrix[(column-1)*4+row]
    end end
    return matrix
  end
  local t=node.translation or {0,0,0}
  local s=node.scale or {1,1,1}
  local q=normalizeQuaternion(node.rotation or {0,0,0,1})
  local x,y,z,w=q[1],q[2],q[3],q[4]
  local rotation={
    {1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w,0},
    {2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w,0},
    {2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y,0},
    {0,0,0,1},
  }
  for row=1,3 do
    rotation[row][1]=rotation[row][1]*(s[1] or 1)
    rotation[row][2]=rotation[row][2]*(s[2] or 1)
    rotation[row][3]=rotation[row][3]*(s[3] or 1)
    rotation[row][4]=t[row] or 0
  end
  return rotation
end

local function transformPoint(matrix,value)
  local x,y,z=value[1] or 0,value[2] or 0,value[3] or 0
  return {matrix[1][1]*x+matrix[1][2]*y+matrix[1][3]*z+matrix[1][4],
    matrix[2][1]*x+matrix[2][2]*y+matrix[2][3]*z+matrix[2][4],
    matrix[3][1]*x+matrix[3][2]*y+matrix[3][3]*z+matrix[3][4]}
end

local function transformNormal(matrix,value)
  local x,y,z=value[1] or 0,value[2] or 0,value[3] or 0
  local nx=matrix[1][1]*x+matrix[1][2]*y+matrix[1][3]*z
  local ny=matrix[2][1]*x+matrix[2][2]*y+matrix[2][3]*z
  local nz=matrix[3][1]*x+matrix[3][2]*y+matrix[3][3]*z
  local length=sqrt(nx*nx+ny*ny+nz*nz)
  if length<=0 then return {0,1,0} end
  return {nx/length,ny/length,nz/length}
end

normalizeQuaternion=function(q)
  local x,y,z,w=q[1] or 0,q[2] or 0,q[3] or 0,q[4] or 1
  local n=sqrt(x*x+y*y+z*z+w*w)
  if n<=0 then return {0,0,0,1} end
  return {x/n,y/n,z/n,w/n}
end

local function sampleValues(times,values,time,interpolation,rotation)
  if #times==0 or #values==0 then return nil end
  local cubic=interpolation=="CUBICSPLINE"
  local function point(index) return values[cubic and ((index-1)*3+2) or index] end
  if time<=times[1] then return point(1) end
  if time>=times[#times] then return point(#times) end
  local right=2
  while right<=#times and times[right]<time do right=right+1 end
  local left=right-1
  if interpolation=="STEP" then return values[left] end
  local span=times[right]-times[left]
  local alpha=span>0 and (time-times[left])/span or 0
  local a,b=point(left),point(right)
  local out={}
  if cubic then
    local dt=span
    local outTangent=values[(left-1)*3+3]
    local inTangent=values[(right-1)*3+1]
    local t2,t3=alpha*alpha,alpha*alpha*alpha
    local h00,h10,h01,h11=2*t3-3*t2+1,t3-2*t2+alpha,-2*t3+3*t2,t3-t2
    for i=1,#a do
      out[i]=h00*a[i]+h10*dt*(outTangent[i] or 0)
        +h01*b[i]+h11*dt*(inTangent[i] or 0)
    end
    return rotation and normalizeQuaternion(out) or out
  end
  if rotation then
    local dot=a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4]
    local sign=dot<0 and -1 or 1
    for i=1,4 do out[i]=a[i]+(b[i]*sign-a[i])*alpha end
    return normalizeQuaternion(out)
  end
  for i=1,#a do out[i]=a[i]+(b[i]-a[i])*alpha end
  return out
end

local function wrapMode(value)
  if value==33648 then return 1 end
  if value==33071 then return 2 end
  return 0
end

local function calculateNormals(prim)
  local normals={}
  for i=1,prim.nverts*3 do normals[i]=0 end
  for at=1,#prim.idx,3 do
    local ia,ib,ic=prim.idx[at],prim.idx[at+1],prim.idx[at+2]
    if ia and ib and ic then
      local ax,ay,az=prim.pos[ia*3-2],prim.pos[ia*3-1],prim.pos[ia*3]
      local bx,by,bz=prim.pos[ib*3-2],prim.pos[ib*3-1],prim.pos[ib*3]
      local cx,cy,cz=prim.pos[ic*3-2],prim.pos[ic*3-1],prim.pos[ic*3]
      local ux,uy,uz=bx-ax,by-ay,bz-az
      local vx,vy,vz=cx-ax,cy-ay,cz-az
      local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
      for _,vertex in ipairs({ia,ib,ic}) do
        normals[vertex*3-2]=normals[vertex*3-2]+nx
        normals[vertex*3-1]=normals[vertex*3-1]+ny
        normals[vertex*3]=normals[vertex*3]+nz
      end
    end
  end
  for vertex=1,prim.nverts do
    local x,y,z=normals[vertex*3-2],normals[vertex*3-1],normals[vertex*3]
    local n=sqrt(x*x+y*y+z*z)
    if n<=0 then x,y,z,n=0,1,0,1 end
    normals[vertex*3-2],normals[vertex*3-1],normals[vertex*3]=x/n,y/n,z/n
  end
  prim.nrm=normals
end

local function modelBounds(model)
  local lo={math.huge,math.huge,math.huge};local hi={-math.huge,-math.huge,-math.huge}
  for _,prim in ipairs(model.prims) do for i=1,prim.nverts do
    for axis=1,3 do
      local value=prim.pos[(i-1)*3+axis]
      lo[axis],hi[axis]=math.min(lo[axis],value),math.max(hi[axis],value)
    end
  end end
  if lo[1]==math.huge then return 1,0,1 end
  local root=math.abs(model.rootScale or 1)
  local radius=math.max(math.abs(lo[1]),math.abs(hi[1]),math.abs(lo[3]),math.abs(hi[3]))*root
  return (hi[2]-lo[2])*root,lo[2]*root,radius
end

local function remapRouting(model,source)
  if not source then return end
  model.handlers=source.handlers
  model.auxAnims=source.auxAnims
  model.context={};model.moveAnim={};model.moveAux={}
  local byName={}
  for index,animation in ipairs(model.anims) do byName[animation.name]=index-1 end
  local function mapped(sourceIndex)
    if sourceIndex==nil or sourceIndex==Pack.NONE then return Pack.NONE end
    local sourceAnimation=source.anims[sourceIndex+1]
    return sourceAnimation and byName[sourceAnimation.name] or Pack.NONE
  end
  for i=1,#Pack.CONTEXTS do model.context[i]=mapped(source.context and source.context[i]) end
  for i=1,Pack.N_MOVES do
    model.moveAnim[i]=mapped(source.moveAnim and source.moveAnim[i])
    model.moveAux[i]=source.moveAux and source.moveAux[i] or -1
  end
end

local function documentModelName(document)
  for _,node in ipairs(document.nodes or {}) do
    local name=tostring(node.name or "")
    local lower=name:lower()
    if name~="" and lower~="rootnode" and lower~="sketchfab_model"
        and lower~="scene" and lower~="active camera" and lower~="default"
        and lower~="untitled" and lower~="empty"
        and not lower:match("^camera ?%d*$") and not lower:match("^plane[%._ ]")
        and not lower:match("^object[_ ]?%d+$")
        and not lower:match("^bone[_ ]?%d+$") and not lower:match("^_?rootjoint$")
        and not lower:match("%.fbx$") then return name end
  end
  for _,mesh in ipairs(document.meshes or {}) do
    local name=tostring(mesh.name or "")
    if name~="" then return name end
  end
  return "GLB model"
end

function Loader.decode(bytes,options)
  options=type(options)=="table" and options or {}
  local container,containerErr=parseContainer(bytes)
  if not container then return nil,containerErr end
  local document=container.document
  local stadium=document.asset and document.asset.extras and document.asset.extras.stadium2 or {}
  local stadiumCompatible=stadium.format==Loader.FORMAT
  if not stadiumCompatible then
    local namedBone,namedMaterial=false,false
    for _,node in ipairs(document.nodes or {}) do
      if tostring(node.name or ""):match("^bone_%d+$") then namedBone=true break end
    end
    for _,material in ipairs(document.materials or {}) do
      if tostring(material.name or ""):match("^material_%d+$") then namedMaterial=true break end
    end
    stadiumCompatible=namedBone and namedMaterial
  end
  local sourceModel=stadiumCompatible and options.sourceModel or nil
  if stadium.sourcePack and stadium.sourcePack.bufferView~=nil then
    local sourceBytes=viewBytes(container,stadium.sourcePack.bufferView)
    if sourceBytes then sourceModel=Pack.parse(sourceBytes) or sourceModel end
  end

  local model={name=options.name or stadium.name or documentModelName(document),
    species=tonumber(options.species) or tonumber(stadium.species)
      or (sourceModel and sourceModel.species) or 0,
    variant=options.variant or stadium.variant or "normal",rootScale=tonumber(stadium.rootScale),
    staticPose=stadium.staticPose==true,rotationFormat="quaternion",bones={},prims={},
    textures={},anims={},animByName={},auxAnims={},context={},moveAnim={},moveAux={}}

  local imageSlots={}
  for imageIndex,image in ipairs(document.images or {}) do
    local encoded,err
    if image.bufferView~=nil then encoded,err=viewBytes(container,image.bufferView)
    else err="external image URIs are unsupported in packaged GLB files" end
    if not encoded then return nil,err end
    local sourceIndex=image.extras and image.extras.stadium2 and image.extras.stadium2.sourceIndex
      or tonumber(tostring(image.name or ""):match("texture_(%d+)$"))
    if sourceIndex then sourceIndex=sourceIndex+((image.extras and image.extras.stadium2) and 0 or 1)
    else sourceIndex=imageIndex end
    local decoded,decodeErr=decodeImage(encoded,image.mimeType or "image/png",imageIndex,options)
    if not decoded then
      decoded=sourceModel and sourceModel.textures and sourceModel.textures[sourceIndex]
      if not decoded then return nil,decodeErr end
    end
    model.textures[sourceIndex]={w=decoded.w,h=decoded.h,rgba=decoded.rgba}
    imageSlots[imageIndex]=sourceIndex
  end
  local textureCount=math.max(#model.textures,
    sourceModel and sourceModel.textures and #sourceModel.textures or 0)
  for index=1,textureCount do
    if not model.textures[index] and sourceModel and sourceModel.textures[index] then
      local texture=sourceModel.textures[index]
      model.textures[index]={w=texture.w,h=texture.h,rgba=texture.rgba}
    end
  end

  local nodes=document.nodes or {}
  local parents={}
  for parent,node in ipairs(nodes) do
    for _,child in ipairs(node.children or {}) do parents[child+1]=parent end
  end
  local skin=document.skins and document.skins[1]
  if skin and #(skin.joints or {})==0 then skin=nil end
  local staticFromSkin=false
  if skin and not stadiumCompatible and #(document.animations or {})==0 then
    staticFromSkin=true
    skin=nil
  end
  local jointMap={}
  for boneIndex,nodeIndex in ipairs(skin and skin.joints or {}) do
    jointMap[nodeIndex+1]=boneIndex-1
  end
  if skin and not stadiumCompatible then
    local worldCache={}
    local function worldNode(index)
      if worldCache[index] then return worldCache[index] end
      local localMatrix=nodeMatrix(nodes[index] or {})
      worldCache[index]=parents[index] and multiply4(worldNode(parents[index]),localMatrix)
        or localMatrix
      return worldCache[index]
    end
    local rootJoint=(skin.joints[1] or 0)+1
    local rootParent=parents[rootJoint]
    if rootParent then model.skinRootMatrix=worldNode(rootParent) end
  end
  if skin and not model.rootScale then
    local rootJoint=(skin.joints[1] or 0)+1
    local ancestor=parents[rootJoint]
    local scale=1
    while ancestor and jointMap[ancestor]==nil do
      local nodeScale=nodes[ancestor] and nodes[ancestor].scale or {1,1,1}
      local sx,sy,sz=nodeScale[1] or 1,nodeScale[2] or 1,nodeScale[3] or 1
      if math.abs(sx-sy)<0.0001 and math.abs(sx-sz)<0.0001 then scale=scale*sx end
      ancestor=parents[ancestor]
    end
    model.rootScale=scale
  end
  if skin then
    for boneIndex,nodeIndex in ipairs(skin.joints) do
      local node=nodes[nodeIndex+1] or {}
      local parent=parents[nodeIndex+1]
      while parent and jointMap[parent]==nil do parent=parents[parent] end
      model.bones[boneIndex]={parent=parent and jointMap[parent] or -1,
        t={unpack(node.translation or {0,0,0})},r=normalizeQuaternion(node.rotation or {0,0,0,1}),
        s={unpack(node.scale or {1,1,1})}}
    end
    if skin.inverseBindMatrices~=nil then
      local inverseValues,inverseErr=accessorValues(container,skin.inverseBindMatrices)
      if not inverseValues then return nil,inverseErr end
      model.inverseBindMatrices=matrixFromAccessor(inverseValues)
    else
      model.inverseBindMatrices={}
      for boneIndex=1,#model.bones do model.inverseBindMatrices[boneIndex]=identity4() end
    end
  else
    -- Ordinary prop/environment GLBs do not need a skin. Their scene-node
    -- transforms are baked into positions below and a neutral renderer bone
    -- keeps them on the same mesh path as animated Stadium models.
    model.bones={{parent=-1,t={0,0,0},r={0,0,0,1},s={1,1,1}}}
    model.inverseBindMatrices={identity4()}
    model.rootScale=model.rootScale or 1
    model.staticPose=true
  end

  local textureToSlot={}
  for textureIndex,texture in ipairs(document.textures or {}) do
    textureToSlot[textureIndex]=imageSlots[(texture.source or 0)+1]
  end
  local meshEntries={}
  if skin then
    for _,mesh in ipairs(document.meshes or {}) do meshEntries[#meshEntries+1]={mesh=mesh} end
  elseif staticFromSkin then
    for _,mesh in ipairs(document.meshes or {}) do
      meshEntries[#meshEntries+1]={mesh=mesh,transform=identity4()}
    end
  else
    local worlds={}
    local function worldMatrix(index)
      if worlds[index] then return worlds[index] end
      local localMatrix=nodeMatrix(nodes[index] or {})
      worlds[index]=parents[index] and multiply4(worldMatrix(parents[index]),localMatrix)
        or localMatrix
      return worlds[index]
    end
    for nodeIndex,node in ipairs(nodes) do
      local mesh=node.mesh~=nil and document.meshes and document.meshes[node.mesh+1]
      if mesh then meshEntries[#meshEntries+1]={mesh=mesh,transform=worldMatrix(nodeIndex)} end
    end
    if #meshEntries==0 then
      for _,mesh in ipairs(document.meshes or {}) do
        meshEntries[#meshEntries+1]={mesh=mesh,transform=identity4()}
      end
    end
  end
  for _,entry in ipairs(meshEntries) do
    local mesh,staticTransform=entry.mesh,entry.transform
    for primitiveIndex,primitive in ipairs(mesh.primitives or {}) do
      if primitive.mode~=nil and primitive.mode~=4 then
        return nil,"only triangle GLB primitives are supported"
      end
      local attributes=primitive.attributes or {}
      local positions,posErr=accessorValues(container,attributes.POSITION)
      if not positions then return nil,posErr or "primitive has no POSITION" end
      local normals=attributes.NORMAL and accessorValues(container,attributes.NORMAL) or nil
      local uvs=attributes.TEXCOORD_0 and accessorValues(container,attributes.TEXCOORD_0) or nil
      local colors=attributes.COLOR_0 and accessorValues(container,attributes.COLOR_0) or nil
      local joints=attributes.JOINTS_0 and accessorValues(container,attributes.JOINTS_0) or nil
      local weights=attributes.WEIGHTS_0 and accessorValues(container,attributes.WEIGHTS_0) or nil
      if not skin then joints,weights=nil,nil end
      local indices
      if primitive.indices~=nil then indices=assert(accessorValues(container,primitive.indices))
      else indices={};for i=0,#positions-1 do indices[#indices+1]=i end end
      local material=document.materials and document.materials[(primitive.material or -1)+1] or {}
      local materialExtras=material.extras and material.extras.stadium2 or {}
      local extras=primitive.extras and primitive.extras.stadium2 or materialExtras
      local sourcePrimitiveIndex=tonumber(tostring(material.name or ""):match("material_(%d+)$"))
      local sourcePrim=sourceModel and sourceModel.prims and sourceModel.prims[
        sourcePrimitiveIndex and sourcePrimitiveIndex+1 or #model.prims+1]
      local base=material.pbrMetallicRoughness and material.pbrMetallicRoughness.baseColorFactor
        or {1,1,1,1}
      local baseTexture=material.pbrMetallicRoughness
        and material.pbrMetallicRoughness.baseColorTexture
      local gltfTexture=baseTexture and document.textures[(baseTexture.index or 0)+1]
      local sampler=gltfTexture and document.samplers and document.samplers[(gltfTexture.sampler or -1)+1]
        or {}
      local lighting=true
      if sourcePrim and sourcePrim.lighting~=nil then lighting=sourcePrim.lighting~=false end
      if material.extensions and material.extensions.KHR_materials_unlit then lighting=false end
      local additive=sourcePrim and sourcePrim.additive==true or false
      if extras.additive~=nil then additive=extras.additive==true end
      local decal=sourcePrim and sourcePrim.decal==true or false
      if extras.decal~=nil then decal=extras.decal==true end
      local prim={nverts=#positions,nidx=#indices,pos={},nrm={},uv={},color={},skin={},
        joints={},weights={},idx={},tex=textureToSlot[(baseTexture and baseTexture.index or -1)+1]
          or tonumber(extras.sourceTexture) or 1,
        cull=material.doubleSided~=true,
        additive=additive,
        lighting=lighting,
        decal=decal,
        effect=extras.effect or sourcePrim and sourcePrim.effect,
        geometryMode=tonumber(extras.geometryMode) or sourcePrim and sourcePrim.geometryMode or 0,
        textureScale=sourcePrim and sourcePrim.textureScale or {1,1},
        sampler={cms=wrapMode(sampler.wrapS),cmt=wrapMode(sampler.wrapT),
          masks=0,maskt=0,shifts=0,shiftt=0},vertexSemantics=colors and "color" or "normal",
        material={primitiveColor={base[1] or 1,base[2] or 1,base[3] or 1,base[4] or 1},
          environmentColor={1,1,1,1},combine={0,0}},
        callbackOffset=extras.callbackOffset or sourcePrim and sourcePrim.callbackOffset,
        materialOffset=extras.materialOffset or sourcePrim and sourcePrim.materialOffset,
        texAnim=tonumber(extras.textureAnimationChannel)
          or sourcePrim and sourcePrim.texAnim or -1,
        texMap=sourcePrim and sourcePrim.texMap,
        fxFrames=extras.effectFrames or sourcePrim and sourcePrim.fxFrames,
        sourceTextureMissing=extras.sourceTextureMissing==true
          or sourcePrim and sourcePrim.sourceTextureMissing==true}
      if sourcePrim then
        prim.material=sourcePrim.material or prim.material
        if not gltfTexture then prim.tex=sourcePrim.tex end
      end
      for vertex,position in ipairs(positions) do
        if staticTransform then position=transformPoint(staticTransform,position) end
        for component=1,3 do prim.pos[#prim.pos+1]=position[component] or 0 end
        local normal=normals and normals[vertex] or {0,0,0}
        if staticTransform and normals then normal=transformNormal(staticTransform,normal) end
        for component=1,3 do prim.nrm[#prim.nrm+1]=normal[component] or 0 end
        local uv=uvs and uvs[vertex] or {0,0}
        prim.uv[#prim.uv+1]=uv[1] or 0
        prim.uv[#prim.uv+1]=uv[2] or 0
        local color=colors and colors[vertex] or {1,1,1,1}
        for component=1,4 do prim.color[#prim.color+1]=floor(math.max(0,math.min(1,
          color[component] or 1))*255+0.5) end
        local jointRow=joints and joints[vertex] or {0,0,0,0}
        local weightRow=weights and weights[vertex] or {1,0,0,0}
        local sum=0;for component=1,4 do sum=sum+(weightRow[component] or 0) end
        if sum<=0 then weightRow={1,0,0,0};sum=1 end
        local dominant,dominantWeight=0,-1
        for component=1,4 do
          local joint=jointRow[component] or 0
          local weight=(weightRow[component] or 0)/sum
          prim.joints[#prim.joints+1],prim.weights[#prim.weights+1]=joint,weight
          if weight>dominantWeight then dominant,dominantWeight=joint,weight end
        end
        prim.skin[vertex]=dominant
      end
      for _,index in ipairs(indices) do prim.idx[#prim.idx+1]=index+1 end
      if not normals then calculateNormals(prim) end
      model.prims[#model.prims+1]=prim
    end
  end
  if #model.prims==0 then return nil,"GLB contains no triangle primitives" end

  for animationIndex,animation in ipairs(document.animations or {}) do
    local duration=0;local decodedSamplers={}
    for samplerIndex,sampler in ipairs(animation.samplers or {}) do
      local times,timeErr=accessorValues(container,sampler.input)
      local values,valueErr=accessorValues(container,sampler.output)
      if not times then return nil,timeErr end;if not values then return nil,valueErr end
      decodedSamplers[samplerIndex]={times=times,values=values,
        interpolation=sampler.interpolation or "LINEAR"}
      duration=math.max(duration,times[#times] or 0)
    end
    local animationExtras=animation.extras and animation.extras.stadium2 or {}
    local frames=tonumber(animationExtras.frameCount) or (floor(duration*30+0.5)+1)
    frames=math.max(1,floor(frames))
    local result={name=animation.name or ("animation_%03d"):format(animationIndex-1),
      frames=frames,loopStart=tonumber(animationExtras.loopStart) or 0,
      aux=animationExtras.auxiliary,tracks={}}
    for _,channel in ipairs(animation.channels or {}) do
      local boneIndex=jointMap[(channel.target.node or -1)+1]
      local path=channel.target.path
      local sampler=decodedSamplers[(channel.sampler or 0)+1]
      if boneIndex~=nil and sampler and (path=="translation" or path=="rotation" or path=="scale") then
        local track=result.tracks[boneIndex+1] or {t={{},{},{}},r={{},{},{},{}},s={{},{},{}}}
        result.tracks[boneIndex+1]=track
        local target=path=="translation" and track.t or path=="rotation" and track.r or track.s
        for frame=0,frames-1 do
          local value=sampleValues(sampler.times,sampler.values,frame/30,
            sampler.interpolation,path=="rotation")
          if value then for component=1,#target do target[component][frame+1]=value[component] end end
        end
      end
    end
    -- Fill missing TRS channels on each animated bone from its rest transform.
    for boneIndex,track in pairs(result.tracks) do
      local bone=model.bones[boneIndex]
      for component=1,3 do
        if #track.t[component]==0 then for frame=1,frames do track.t[component][frame]=bone.t[component] end end
        if #track.s[component]==0 then for frame=1,frames do track.s[component][frame]=bone.s[component] end end
      end
      for component=1,4 do
        if #track.r[component]==0 then for frame=1,frames do track.r[component][frame]=bone.r[component] end end
      end
    end
    result.seconds=frames/30
    model.anims[#model.anims+1]=result
    if model.animByName[result.name]==nil then model.animByName[result.name]=#model.anims end
  end
  remapRouting(model,sourceModel)
  model.boneCount,model.primCount,model.texCount,model.animCount=
    #model.bones,#model.prims,#model.textures,#model.anims
  model.height=model.height or tonumber(stadium.height)
    or sourceModel and sourceModel.height
  model.floor=model.floor or tonumber(stadium.floor)
    or sourceModel and sourceModel.floor
  model.radius=model.radius or tonumber(stadium.radius)
    or sourceModel and sourceModel.radius
  if not (model.height and model.floor and model.radius) then
    model.height,model.floor,model.radius=modelBounds(model)
  end
  model.sourceFormat="glb"
  model.genericGLB=not stadiumCompatible
  if model.genericGLB then model.battleDisplayHeight=12 end
  return model
end

Loader.decodeJSON=decodeJSON
Loader.parseContainer=parseContainer
Loader.accessorValues=accessorValues

return Loader
