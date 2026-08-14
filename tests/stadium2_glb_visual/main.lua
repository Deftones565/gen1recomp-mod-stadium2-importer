-- Interactive development viewer for a Blender-edited GLB. This test is not
-- part of the packaged mod, so host file access is intentional here.
local function exists(path)
  local file=io.open(path,"rb")
  if not file then return false end
  file:close();return true
end

local function read(path)
  local file,err=io.open(path,"rb");assert(file,err)
  local bytes=file:read("*a");file:close();return bytes
end

local root=os.getenv("GEN1RECOMP_ROOT") or love.filesystem.getWorkingDirectory()
assert(exists(root.."/mods/STADIUM2_IMPORTER/lib/glb_loader.lua"),
  "run from the Gen1Recomp root or set GEN1RECOMP_ROOT")
package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path

local Loader=require("mods.STADIUM2_IMPORTER.lib.glb_loader")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local Viewer=require("mods.STADIUM2_IMPORTER.tests.model_viewer")
local modRoot=root.."/mods/STADIUM2_IMPORTER/"
local target=os.getenv("STADIUM2_VISUAL_GLB")
  or (modRoot.."build/blender-roundtrip/025-normal.glb")
if target:sub(1,1)~="/" then target=root.."/"..target end
local filename=target:match("([^/]+)$") or target
local species=tonumber(filename:match("^(%d%d%d)")) or 0
local variant=filename:find("shiny",1,true) and "shiny" or "normal"
local shaderStyle=os.getenv("STADIUM2_VISUAL_SHADER")=="cel" and "cel" or "stadium"
local viewer,model,loadError
local autoClose=tonumber(os.getenv("STADIUM2_VISUAL_AUTOCLOSE"))
local elapsed=0

local function loadModel()
  local sourceModel
  local sourcePath=os.getenv("STADIUM2_VISUAL_SOURCE_GLB")
  if sourcePath and sourcePath:sub(1,1)~="/" then sourcePath=root.."/"..sourcePath end
  if not sourcePath then
    local inferred=modRoot.."build/glb/"..filename
    if inferred~=target and exists(inferred) then sourcePath=inferred end
  end
  if sourcePath and exists(sourcePath) then
    sourceModel=assert(Loader.decode(read(sourcePath),{species=species,variant=variant}))
  end
  model=assert(Loader.decode(read(target),{
    species=species,variant=variant,sourceModel=sourceModel}))
end

local function buildViewer()
  local importer={}
  function importer.configure() end
  function importer.available() return true end
  function importer.status() return {state="ready"} end
  function importer.newRenderer(_,_,options)
    options=options or {};options.shaderStyle=shaderStyle
    return Renderer.new(model,options)
  end
  viewer=Viewer.new(nil,importer)
  viewer.entry=math.max(1,(math.max(1,species)-1)*2+(variant=="shiny" and 2 or 1))
  viewer.species,viewer.variant=species,variant
end

function love.load()
  love.graphics.setDefaultFilter("nearest","nearest")
  local ok,err=pcall(function() loadModel();buildViewer() end)
  if not ok then loadError=tostring(err);print("GLB visual viewer: "..loadError) end
end

function love.update(dt)
  if viewer then viewer:update(dt) end
  elapsed=elapsed+dt
  if autoClose and elapsed>=autoClose then love.event.quit(loadError and 1 or 0) end
end

function love.draw()
  if viewer then
    viewer:draw()
    local g=love.graphics
    g.setColor(0.018,0.022,0.032,0.96)
    g.rectangle("fill",0,g.getHeight()-50,g.getWidth(),50)
    g.setColor(0.9,0.92,0.98,1)
    g.printf(filename.."   shader: "..shaderStyle
      .."   Q/E animation   SPACE pause   V shader   wheel zoom   left drag move   right drag orbit",
      12,g.getHeight()-35,g.getWidth()-24,"center")
  else
    love.graphics.clear(0.02,0.02,0.03,1)
    love.graphics.setColor(1,0.4,0.4,1)
    love.graphics.printf("GLB viewer failed:\n\n"..tostring(loadError),40,80,
      love.graphics.getWidth()-80,"center")
  end
end

function love.keypressed(key)
  if key=="escape" then love.event.quit()
  elseif key=="v" and viewer then
    shaderStyle=shaderStyle=="cel" and "stadium" or "cel"
    viewer:loadEntry();viewer.species,viewer.variant=species,variant
  elseif viewer and (key=="q" or key=="pageup" or key=="[") then viewer:previousAnimation()
  elseif viewer and (key=="e" or key=="pagedown" or key=="]") then viewer:nextAnimation()
  elseif viewer and (key=="space" or key=="r" or key=="=" or key=="+"
      or key=="kp+" or key=="-" or key=="_" or key=="kp-") then
    viewer:onKeyPressed(key)
  end
end

function love.wheelmoved(x,y) if viewer then viewer:onWheelMoved(x,y) end end
function love.mousepressed(x,y,button) if viewer then viewer:onMousePressed(x,y,button) end end
function love.mousemoved(x,y) if viewer then viewer:onMouseMoved(x,y) end end
function love.mousereleased(x,y,button) if viewer then viewer:onMouseReleased(x,y,button) end end
function love.quit() if viewer then viewer:releaseRig() end end
