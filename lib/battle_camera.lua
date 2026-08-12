local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Camera = {}

-- The 3D battle is a widescreen composition, not a 160-pixel Game Boy
-- screenshot stretched until it fills the display.  The established wide
-- battle path uses a 304x144 surface to choose the integer pixel
-- scale, then keeps the classic 160x144 battle coordinates centred inside it.
-- Do the same here: HUD blocks still use Gold's native coordinates, but their
-- screen-pixel size is solved against the wide surface so a large/tall display
-- cannot make the two snapped status bands enormous and crowd the scene.
Camera.WIDE_UI_WIDTH = 304
Camera.UI_WIDTH = 160
Camera.UI_HEIGHT = 144

function Camera.fitScale(width, height)
  width = math.max(1, tonumber(width) or 1)
  height = math.max(1, tonumber(height) or 1)
  return math.max(1, math.floor(math.min(
    width / Camera.WIDE_UI_WIDTH, height / Camera.UI_HEIGHT)))
end

function Camera.fitOrigin(width, height, scale)
  scale = scale or Camera.fitScale(width, height)
  return math.floor((width - Camera.UI_WIDTH * scale) / 2),
    math.floor((height - Camera.UI_HEIGHT * scale) / 2)
end

Camera.positions = { player={0,0,24}, enemy={0,0,-24} }
Camera.RIG = { side=41.98, back=41.16, height=28.48,
  -- Renderer.perspective uses a true vertical field.  53.40 is the solved
  -- span that lands these world marks at Gold's (26,96) and (124,56).
  lookX=-3.24, lookY=-1.35, frameH=53.40 }
Camera.PAN_YAW = math.rad(2)
Camera.PAN_PERIOD = 26
Camera.PAN_DOLLY = 0.02
Camera.DOLLY_PERIOD = 37
Camera.ORBIT_TIME = .22
Camera.ORBIT_DRAG = 1.15
Camera.ORBIT_MOUSE = .0011
Camera.ORBIT_STICK = .9
Camera.PITCH_RANGE = math.rad(45)
Camera.PITCH_TIME = .22
Camera.PITCH_DRAG = 1.6
Camera.PITCH_MOUSE = .0016
Camera.PITCH_STICK = .9
Camera.STICK_DEAD = .2
Camera.ZOOM_MIN = .45
Camera.ZOOM_MAX = 2
Camera.ZOOM_STEP = 1.15
Camera.ZOOM_TIME = .18

local state = { time=0, orbit=0, orbitGoal=0, pitch=0, pitchGoal=0,
  zoom=1, zoomGoal=1 }
local tau = math.pi * 2
local LOVE_CANVAS_Y = {1,0,0,0, 0,-1,0,0, 0,0,1,0, 0,0,0,1}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, tonumber(v) or lo))
end

local function chase(now, goal, dt, time)
  if now == goal then return goal end
  local value = now + (goal-now) * math.min(1, (dt or 0) / time)
  return math.abs(goal-value)<1e-4 and goal or value
end

function Camera.orbit(delta)
  state.orbitGoal = clamp(state.orbitGoal + (tonumber(delta) or 0), 0, 1)
  return state.orbitGoal
end

function Camera.pitch(delta)
  state.pitchGoal = clamp(state.pitchGoal + (tonumber(delta) or 0), 0, 1)
  return state.pitchGoal
end

function Camera.zoom(factor)
  state.zoomGoal = clamp(state.zoomGoal * (tonumber(factor) or 1),
    Camera.ZOOM_MIN, Camera.ZOOM_MAX)
  return state.zoomGoal
end

function Camera.reset()
  state.time = 0
end

function Camera.recentre()
  state.orbit,state.orbitGoal=0,0
  state.pitch,state.pitchGoal=0,0
  state.zoom,state.zoomGoal=1,1
end

function Camera.mouseOrbit(dx)
  return Camera.orbit((tonumber(dx) or 0)*Camera.ORBIT_MOUSE)
end

function Camera.dragOrbit(fraction)
  return Camera.orbit((tonumber(fraction) or 0)*Camera.ORBIT_DRAG)
end

function Camera.dragPitch(fraction)
  return Camera.pitch((tonumber(fraction) or 0)*Camera.PITCH_DRAG)
end

function Camera.mousePitch(dy)
  return Camera.pitch((tonumber(dy) or 0)*Camera.PITCH_MOUSE)
end

local function stickCurve(value)
  value=tonumber(value) or 0
  local amount=math.abs(value)
  if amount<Camera.STICK_DEAD then return 0 end
  amount=(amount-Camera.STICK_DEAD)/(1-Camera.STICK_DEAD)
  return (value<0 and -1 or 1)*amount*amount
end

function Camera.stickOrbit(value,dt)
  return Camera.orbit(stickCurve(value)*Camera.ORBIT_STICK*(dt or 0))
end

function Camera.stickPitch(value,dt)
  return Camera.pitch(stickCurve(value)*Camera.PITCH_STICK*(dt or 0))
end

-- Positive notches pull out; negative notches move in.
function Camera.stepZoom(notches)
  return Camera.zoom(Camera.ZOOM_STEP^(tonumber(notches) or 0))
end

function Camera.update(dt)
  dt=math.max(0,tonumber(dt) or 0)
  state.time=state.time+dt
  local wrap=Camera.PAN_PERIOD*Camera.DOLLY_PERIOD
  if state.time>wrap then state.time=state.time-wrap end
  state.orbit=chase(state.orbit,state.orbitGoal,dt,Camera.ORBIT_TIME)
  state.pitch=chase(state.pitch,state.pitchGoal,dt,Camera.PITCH_TIME)
  state.zoom=chase(state.zoom,state.zoomGoal,dt,Camera.ZOOM_TIME)
end

local function orbitRange()
  return math.max(0,math.pi/2-math.atan2(Camera.RIG.side,Camera.RIG.back))
end

local function axisSpan(beta,elevation)
  local c=math.cos(elevation)
  local horizontal=math.sin(beta)*c
  local vertical=math.sin(elevation)
  return math.sqrt(horizontal*horizontal+vertical*vertical)
end

local function spread()
  local rig=Camera.RIG
  local beta=math.atan2(rig.side,rig.back)
  local elevation=math.atan2(rig.height-rig.lookY,
    math.sqrt((rig.side-rig.lookX)^2+rig.back^2))
  local home=axisSpan(beta,elevation)
  if home<1e-6 then return 1 end
  return axisSpan(beta+state.orbit*orbitRange(),
    elevation+state.pitch*Camera.PITCH_RANGE)/home
end

function Camera.frame(width, height)
  local rig = Camera.RIG
  local drift = math.sin(state.time * tau / Camera.PAN_PERIOD) * Camera.PAN_YAW
  local yaw = drift-state.orbit*orbitRange()
  local breathe = 1 + math.sin(state.time * tau / Camera.DOLLY_PERIOD)
    * Camera.PAN_DOLLY
  local c, s = math.cos(yaw), math.sin(yaw)
  local side, back = rig.side * breathe, rig.back * breathe
  local ex, ez = side*c-back*s, side*s+back*c
  local baseDist = math.sqrt(ex*ex + rig.height*rig.height + ez*ez)
  local eyeY = rig.height
  local lift=state.pitch*Camera.PITCH_RANGE
  if lift>0 then
    local vx,vy,vz=ex-rig.lookX,eyeY-rig.lookY,ez
    local flat=math.sqrt(vx*vx+vz*vz)
    local radius=math.sqrt(flat*flat+vy*vy)
    if flat>1e-6 and radius>1e-6 then
      local angle=math.min(math.atan2(vy,flat)+lift,math.rad(85))
      local nextFlat=radius*math.cos(angle)
      ex=rig.lookX+vx/flat*nextFlat
      ez=vz/flat*nextFlat
      eyeY=rig.lookY+radius*math.sin(angle)
    end
  end
  local view = Renderer.lookAt(ex, eyeY, ez, rig.lookX, rig.lookY, 0)
  local fov144 = 2 * math.atan((rig.frameH*state.zoom*spread()/2)/baseDist)
  local fit = Camera.fitScale(width, height)
  local span = 144 * fit
  local fov = span > 0
    and 2 * math.atan(math.tan(fov144 / 2) * height / span) or fov144
  -- Renderer.perspective is textbook GL clip space (+Y up).  drawScene sends
  -- that matrix directly from the vertex shader, bypassing LOVE's normal
  -- transform_projection, while a LOVE Canvas has +Y down.  Flip clip Y once
  -- here so all Gold world meshes share the canvas convention.  Leaving this
  -- out mirrors both the Pokemon and their platform vertically.
  local projection = Renderer.matMul(LOVE_CANVAS_Y,
    Renderer.perspective(fov, width / math.max(1, height),.1,1000))
  local ox, oy = Camera.fitOrigin(width, height, fit)
  return {
    view=view, projection=projection,
    vp=Renderer.matMul(projection, view),
    eye={ex,eyeY,ez}, focus={rig.lookX,rig.lookY,0},
    letterbox={lx=ox,ly=oy,scale=fit,pw=width,ph=height},
  }
end

function Camera.project(frame, width, height, point)
  local vp, x, y, z = frame.vp, point[1], point[2], point[3]
  local cx = vp[1]*x + vp[2]*y + vp[3]*z + vp[4]
  local cy = vp[5]*x + vp[6]*y + vp[7]*z + vp[8]
  local cw = vp[13]*x + vp[14]*y + vp[15]*z + vp[16]
  if cw <= .001 then return width/2, height/2, false end
  -- Clip Y has already been converted to LOVE's down-positive convention.
  return (cx/cw*.5+.5)*width, (cy/cw*.5+.5)*height, true
end

function Camera.state() return state end

return Camera
