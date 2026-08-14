-- Development-only integration audit. This intentionally uses io to read
-- ignored build artifacts; none of this directory is loaded by the mod.
local function read(path)
  local file,err=io.open(path,"rb")
  assert(file,err)
  local bytes=file:read("*a")
  file:close()
  return bytes
end

local root=os.getenv("GEN1RECOMP_ROOT") or love.filesystem.getWorkingDirectory()
package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path

local Loader=require("mods.STADIUM2_IMPORTER.lib.glb_loader")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local importerPath=root.."/mods/STADIUM2_IMPORTER/"

function love.errorhandler(message)
  print("GLB runtime audit FAIL: "..tostring(message))
  return function() love.event.quit(1) end
end

function love.load()
  io.stdout:setvbuf("no")
  print("GLB runtime audit: decode original")
  local original=assert(Loader.decode(read(importerPath.."build/glb/025-normal.glb"),
    {species=25,variant="normal"}))
  print("GLB runtime audit: decode Blender edit")
  local edited=assert(Loader.decode(read(importerPath.."build/blender-roundtrip/025-normal.glb"),
    {species=25,variant="normal",sourceModel=original}))
  assert(#edited.prims>0 and #edited.bones>0 and #edited.anims>0,"edited GLB is incomplete")
  assert(#edited.textures==#original.textures,
    "callback-only source textures were not restored")
  assert(math.abs((edited.rootScale or 0)-0.0999908447)<0.0001,
    "Blender scene root scale was not recovered")
  assert(math.abs(edited.height-original.height)<0.0001
      and math.abs(edited.floor-original.floor)<0.0001
      and math.abs(edited.radius-original.radius)<0.0001,
    "Stadium battle bounds were not restored after Blender stripped extras")
  assert(edited.prims[1].pos[1]~=original.prims[1].pos[1],
    "Blender vertex edit did not survive re-export")
  for index,primitive in ipairs(edited.prims) do
    local source=original.prims[index]
    assert(source and primitive.callbackOffset==source.callbackOffset
      and primitive.materialOffset==source.materialOffset
      and primitive.texAnim==source.texAnim
      and primitive.additive==source.additive
      and primitive.decal==source.decal
      and primitive.lighting==source.lighting,
      "Stadium metadata was not restored for primitive "..index)
  end
  print("GLB runtime audit: create renderer")
  local renderer=assert(Renderer.new(edited,{shaderStyle="stadium"}))
  print("GLB runtime audit: draw")
  local drawOK,drawErr=pcall(renderer.draw,renderer,0,0,256,256,{})
  assert(drawOK,drawErr)
  renderer:release()
  local mobileRenderer=assert(Renderer.new(edited,{simpleMobileShader=true}))
  assert(mobileRenderer.shaderTier=="mobile-simple","mobile GLB shader was not selected")
  local mobileOK,mobileErr=pcall(mobileRenderer.draw,mobileRenderer,0,0,256,256,{})
  assert(mobileOK,mobileErr)
  mobileRenderer:release()
  print(("GLB runtime audit: %d primitives, %d bones, %d animations, rootScale=%.8f, desktop+mobile draw=ok")
    :format(#edited.prims,#edited.bones,#edited.anims,edited.rootScale))
  love.event.quit(0)
end
