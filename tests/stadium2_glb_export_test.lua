package.path="./?.lua;./?/init.lua;"..package.path

local Build=require("mods.STADIUM2_IMPORTER.lib.build")
local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
local GLB=require("mods.STADIUM2_IMPORTER.lib.glb")
local GLBLoader=require("mods.STADIUM2_IMPORTER.lib.glb_loader")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end
local function u32(bytes,offset)
  local a,b,c,d=bytes:byte(offset,offset+3)
  return a+b*256+c*65536+d*16777216
end
local function le32(value)
  return string.char(value%256,math.floor(value/256)%256,
    math.floor(value/65536)%256,math.floor(value/16777216)%256)
end
local function rawGLB(json,binary)
  json=json..string.rep(" ",(4-#json%4)%4)
  binary=binary..string.rep("\0",(4-#binary%4)%4)
  local body=le32(#json).."JSON"..json..le32(#binary).."BIN\0"..binary
  return "glTF"..le32(2)..le32(12+#body)..body
end

local moveRows={}
for i=1,165 do moveRows[i]={0,0} end
local contexts={}
for i=1,#Build.CONTEXTS do contexts[i]=0xFFFF end
contexts[1]=0
local packed=Build.pack({
  rootScale={0.1,0.1,0.1},
  bones={
    {parent=-1,t={0,2,0},r={0,0,0},s={1,1,1}},
    {parent=0,t={4,0,0},r={0,0,0},s={1,1,1}},
  },
  prims={{tex=0,cull=1,blend="add",lighting=true,decal=true,
    geometryMode=0,sampler={cms=0,cmt=1,masks=0,maskt=0,shifts=0,shiftt=0},
    textureScale={1,1},texAnim=-1,vertexSemantics="color",
    pos={0,0,0,10,0,0,0,10,0},uv={0,0,1,0,0,1},
    nrm={0,0,1,0,0,1,0,0,1},
    color={255,0,0,255,0,255,0,255,0,0,255,128},
    skin={0,1,1},nverts=3,idx={0,1,2},nidx=3}},
  textures={{w=2,h=1,rgba="\255\0\0\255\0\255\0\128"},
    {w=1,h=1,rgba="\0\0\255\255"}},
  anims={{name="idle",frames=2,loopStart=1,aux=0,tracks={
    [2]={t={{4,6},0,0},r={0,{0,8192},0},s={1,1,1}},
  }}},
  auxAnims={},handlerOps={},
},25,moveRows,contexts)
local model=assert(Pack.parse(packed))
model.variant="normal"
local bytes,summary=assert(GLB.encode(model,{name="pikachu",variant="normal"}))
ok(bytes:sub(1,4)=="glTF" and u32(bytes,5)==2,"GLB 2.0 header")
ok(u32(bytes,9)==#bytes,"GLB declared length matches payload")
local jsonLength=u32(bytes,13)
ok(bytes:sub(17,20)=="JSON","JSON chunk tag")
local json=bytes:sub(21,20+jsonLength)
local binaryHeader=21+jsonLength
ok(bytes:sub(binaryHeader+4,binaryHeader+7)=="BIN\0","binary chunk tag")
ok(json:find('"generator":"STADIUM2_IMPORTER STADIUM2_GLTF_1"',1,true),
  "export identifies the Stadium GLB contract")
ok(json:find('"POSITION"',1,true) and json:find('"JOINTS_0"',1,true)
    and json:find('"WEIGHTS_0"',1,true) and json:find('"COLOR_0"',1,true),
  "mesh carries geometry, rigid skinning, and vertex color attributes")
ok(json:find('"inverseBindMatrices"',1,true) and json:find('"skin":0',1,true),
  "skeleton uses standard glTF skin data")
ok(json:find('"name":"idle"',1,true) and json:find('"path":"rotation"',1,true)
    and json:find('"frameCount":2',1,true) and json:find('"loopStart":1',1,true),
  "named animation and Stadium loop metadata are preserved")
ok(json:find('"additive":true',1,true) and json:find('"decal":true',1,true)
    and json:find('"wrapT":"mirroredrepeat"',1,true),
  "nonstandard Stadium material behavior survives in extras")
ok(json:find('"mimeType":"image/png"',1,true),"RGBA texture is embedded as PNG")
ok(json:find('"sourceIndex":2',1,true),
  "unreferenced callback and animation textures remain embedded")
ok(json:find('"mimeType":"application/x-stadium2-dsm4"',1,true),
  "source DSM pack is retained for lossless Stadium-specific reconstruction")
ok(summary.species==25 and summary.primitives==1 and summary.textures==2
    and summary.bones==2 and summary.animations==1,"export summary reports model contents")
local again=assert(GLB.encode(model,{name="pikachu",variant="normal"}))
ok(bytes==again,"GLB encoding is deterministic and does not mutate the model")
local png=assert(GLB.png(model.textures[1]))
ok(png:sub(1,8)=="\137PNG\r\n\26\n" and png:find("IHDR",1,true)
    and png:find("IDAT",1,true) and png:find("IEND",1,true),
  "pure-Lua PNG encoder emits required chunks")
ok(GLB.jsonEncode({romBytes="\255\128"}):find("\\u00ff\\u0080",1,true),
  "arbitrary ROM metadata bytes remain valid UTF-8 JSON through escapes")

local staticBinary=Build.f32(0)..Build.f32(0)..Build.f32(0)
  ..Build.f32(1)..Build.f32(0)..Build.f32(0)
  ..Build.f32(0)..Build.f32(1)..Build.f32(0).."\0\0\1\0\2\0"
local staticJSON='{"asset":{"version":"2.0"},"buffers":[{"byteLength":42}],'
  ..'"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},'
  ..'{"buffer":0,"byteOffset":36,"byteLength":6}],'
  ..'"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
  ..'{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],'
  ..'"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}],'
  ..'"nodes":[{"mesh":0,"translation":[2,0,0],"scale":[2,2,2]}],'
  ..'"scenes":[{"nodes":[0]}],"scene":0}'
local staticModel,staticErr=GLBLoader.decode(rawGLB(staticJSON,staticBinary))
ok(staticModel~=nil,staticErr or "ordinary static GLB loads without a skin or texture")
ok(staticModel.staticPose and #staticModel.bones==1 and #staticModel.prims==1,
  "static GLB receives a neutral renderer bone")
ok(staticModel.prims[1].pos[1]==2 and staticModel.prims[1].pos[4]==4,
  "static GLB scene-node translation and scale are applied")
ok(Renderer.new(staticModel)~=nil,"ordinary static GLB uses the shared renderer")

local loaded,loadErr=GLBLoader.decode(bytes,{imageDecoder=function(_,_,index)
  local texture=model.textures[index]
  return {w=texture.w,h=texture.h,rgba=texture.rgba}
end})
ok(loaded~=nil,loadErr or "exported GLB loads back into the mod")
ok(loaded.sourceFormat=="glb" and loaded.rotationFormat=="quaternion"
    and loaded.species==25 and #loaded.prims==1 and #loaded.bones==2,
  "GLB loader rebuilds the renderer model contract")
ok(#loaded.prims[1].joints==loaded.prims[1].nverts*4
    and #loaded.prims[1].weights==loaded.prims[1].nverts*4,
  "GLB loader retains four-weight skinning")
ok(loaded.anims[1] and loaded.anims[1].name=="idle"
    and #loaded.anims[1].tracks[2].r==4,
  "GLB animation loads as quaternion tracks")
local sourceRig=assert(Renderer.new(model))
local loadedRig=assert(Renderer.new(loaded))
local function sameRows(a,b)
  for row=1,#a do for component=1,8 do
    if math.abs((a[row][component] or 0)-(b[row][component] or 0))>0.0001 then return false end
  end end
  return true
end
ok(sameRows(sourceRig.parts[1].rows,loadedRig.parts[1].rows),
  "GLB inverse-bind skinning reproduces the DSM bind pose")
sourceRig:seekFrame(1);loadedRig:seekFrame(1)
ok(sameRows(sourceRig.parts[1].rows,loadedRig.parts[1].rows),
  "quaternion GLB animation reproduces the source animated pose")

local weighted=assert(GLBLoader.decode(bytes,{imageDecoder=function(_,_,index)
  local texture=model.textures[index]
  return {w=texture.w,h=texture.h,rgba=texture.rgba}
end}))
weighted.prims[1].joints[1],weighted.prims[1].joints[2]=0,1
weighted.prims[1].weights[3],weighted.prims[1].weights[4]=0,0
local function animatedX(first,second)
  weighted.prims[1].weights[1],weighted.prims[1].weights[2]=first,second
  local rig=assert(Renderer.new(weighted));rig:seekFrame(1)
  return rig.parts[1].rows[1][1]
end
local joint0X,joint1X=animatedX(1,0),animatedX(0,1)
local blendedX=animatedX(0.5,0.5)
ok(math.abs(blendedX-(joint0X+joint1X)*0.5)<0.0001,
  "renderer linearly blends a vertex across two animated GLB joints")
local reencoded=assert(GLB.encode(loaded,{name="quaternion-roundtrip"}))
ok(reencoded:sub(1,4)=="glTF",
  "loaded quaternion animations can be exported again")

local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local records={}
local mod={game={save={version="red",meta={playthroughId="glb-test"}}}}
function mod:read(path)
  if path=="models/025-normal.glb" then return bytes end
end
mod.storage={}
function mod.storage:context() return {gameVersion="red",playthroughId="glb-test"} end
function mod.storage:read(_,key) return records[key] end
function mod.storage:write(_,key,value) records[key]=value;return true end
function mod.storage:delete(_,key) records[key]=nil;return true end
Importer.bind(mod)
local packaged,packagedErr=Importer.loadModel(25,"normal")
ok(packaged~=nil,packagedErr or "packaged GLB model loads through importer")
ok(packaged.sourceFormat=="glb" and packaged.packagedPath=="models/025-normal.glb",
  "packaged GLB overrides the generated DSM cache path")
local packagedRenderer,rendererErr=Importer.newRenderer(25,"normal")
ok(packagedRenderer~=nil,rendererErr or "packaged GLB uses the battle renderer")

print(("%d checks passed (Stadium 2 GLB export)"):format(checks))
