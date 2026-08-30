local Runtime = require("src.mods.Runtime")
local Sky = require("mods.STADIUM2_IMPORTER.lib.battle_sky")

local Background = {}

Background.HOOK = "battle.scene.background.v1"
Background.API_VERSION = 1

local function horizonY(frame,height)
  local m=frame and frame.vp
  local eye=frame and frame.eye
  local focus=frame and frame.focus
  if not (m and eye and focus and height and height>0) then return nil end
  local dx=(focus[1] or 0)-(eye[1] or 0)
  local dz=(focus[3] or 0)-(eye[3] or 0)
  local len=math.sqrt(dx*dx+dz*dz)
  if len<1e-6 then return nil end
  dx,dz=dx/len,dz/len
  local y=m[5]*dx+m[7]*dz
  local w=m[13]*dx+m[15]*dz
  if w<=1e-6 then return nil end
  return (y/w*.5+.5)*height
end

local function resetState(g)
  if g.setShader then g.setShader() end
  if g.setDepthMode then g.setDepthMode("always",false) end
  if g.setMeshCullMode then g.setMeshCullMode("none") end
  if g.setBlendMode then g.setBlendMode("alpha","alphamultiply") end
  if g.setColor then g.setColor(1,1,1,1) end
end

function Background.context(g,renderWidth,renderHeight,logicalWidth,logicalHeight,environment,frame)
  local sx=renderWidth/math.max(1,logicalWidth or renderWidth)
  local sy=renderHeight/math.max(1,logicalHeight or renderHeight)
  local uiScale=frame and frame.letterbox and frame.letterbox.scale or 1
  return {
    apiVersion=Background.API_VERSION,
    kind="sky",
    graphics=g,
    width=renderWidth,
    height=renderHeight,
    logicalWidth=logicalWidth,
    logicalHeight=logicalHeight,
    pixelScale={x=sx,y=sy},
    pixelGrid=math.max(1,math.floor(uiScale*sy+.5)),
    environment=environment,
    camera={
      view=frame and frame.view,
      projection=frame and frame.projection,
      viewProjection=frame and frame.vp,
      eye=frame and frame.eye,
      focus=frame and frame.focus,
      horizonY=horizonY(frame,renderHeight),
    },
  }
end

function Background.draw(g,renderWidth,renderHeight,logicalWidth,logicalHeight,environment,frame)
  local bands=environment and environment.bands
  local clear=bands and bands[1] or {0,0,0}
  resetState(g)
  g.clear(clear[1] or 0,clear[2] or 0,clear[3] or 0,1,true,true)

  local ctx=Background.context(g,renderWidth,renderHeight,logicalWidth,logicalHeight,
    environment,frame)
  local result=Runtime.call(Background.HOOK,function(request)
    Sky.draw(g,renderWidth,renderHeight,environment,frame,{precleared=true})
    return true
  end,ctx)
  resetState(g)
  return result
end

return Background
