local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local StadiumBattleLayout = require("mods.STADIUM2_IMPORTER.lib.stadium_battle_layout")
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

-- Stadium 2's battle overlay (US fragment 79, func_8410AE8C) configures the
-- world cameras with these perspective values before submitting their eye and
-- target vectors to the engine look-at routine.  They are source-space N64
-- units; arenaFrame scales the clip planes by the same conversion used for
-- the extracted field and Pokemon geometry.
Camera.STADIUM = {
  fov=math.rad(45), near=20, far=6400,
  viewportWidth=320, viewportHeight=240,
  -- The ordinary two-battler field shot.  Fragment 79 authors battlers along
  -- X and looks across that line from the player's side of the field.  Keep
  -- this pose in source units so arenaScale is the sole unit conversion.
  eye={-420,260,520}, focus={0,62,0},
  -- D_8418455C: the 21 camera families consumed by fragment 79. Each row is
  -- pitch A, yaw A, distance A, pitch B, yaw B, distance B, FOV, follow, pan.
  -- Angles use the N64's signed 16-bit turn representation.
  presets={
    {1536,0,1.8,1536,0,1.8,45,.2,.03},
    {1536,-10922,2,1536,-10922,2,45,.2,.03},
    {5120,0,1.8,5120,0,1.8,45,.2,.03},
    {5120,-10922,1.8,5120,-10922,1.8,45,.2,.03},
    {1536,0,1.8,1536,0,1.8,60,.2,.03},
    {1536,-29127,2.4,1536,-29127,2.4,45,.2,.03},
    {1536,-3640,2,1536,-3640,2,45,.2,.03},
    {5120,-3640,2,5120,-3640,2,45,.2,.03},
    {5461,-29127,2,5461,-29127,2,45,.2,.03},
    {-1536,-3640,2,-1536,-3640,2,45,.2,.03},
    {10922,0,3.2,1536,0,1.8,45,.2,.03},
    {7281,-12743,3.2,1536,0,1.8,45,.2,.03},
    {1536,-10922,2.5,1536,0,1.8,45,.2,.03},
    {16016,0,2.4,1536,0,1.8,45,.2,.02},
    {1536,0,1.8,3640,-32396,3.2,45,.2,.03},
    {2048,0,4,2048,0,1.3,45,.2,.03},
    {1536,0,1.8,16016,0,2.4,45,.2,.02},
    {-1536,-9102,2,3276,0,1.8,45,.2,.03},
    {1536,0,1.8,9102,-12743,1.8,45,.2,.03},
    {-1536,-9102,2,14563,0,1.8,45,.2,.03},
    {1536,-9102,2,10922,-18204,1.8,45,.2,.03},
  },
}

function Camera.fitScale(width, height)
  width = math.max(1, tonumber(width) or 1)
  height = math.max(1, tonumber(height) or 1)
  -- Battle Art keeps portrait as the native 160x144 composition and lets the
  -- background crop around it. Landscape retains Stadium's established
  -- 304x144 wide field. Measure the rung in framebuffer pixels like the
  -- engine Renderer, then convert it back to LOVE units for this compositor.
  local baseWidth=height>width*1.20 and Camera.UI_WIDTH
    or Camera.WIDE_UI_WIDTH
  local dpi,pw,ph=1,width,height
  if love and love.graphics and love.graphics.getDimensions
      and love.graphics.getPixelDimensions then
    local ok,w,h=pcall(love.graphics.getDimensions)
    local pok,fullPw,fullPh=pcall(love.graphics.getPixelDimensions)
    if ok and pok and tonumber(w) and tonumber(h) and w>0 and h>0
        and tonumber(fullPw) and tonumber(fullPh) then
      local dx,dy=fullPw/w,fullPh/h
      dpi=math.max(1e-6,math.min(dx,dy))
      pw,ph=width*dx,height*dy
    end
  end
  local physical=math.max(1,math.floor(math.min(
    pw/baseWidth,ph/Camera.UI_HEIGHT)))
  return physical/dpi
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
  zoom=1, zoomGoal=1, arenaMode=0, arenaTarget="enemy" }
local sceneFrameContext
local tau = math.pi * 2
local LOVE_CANVAS_Y = {1,0,0,0, 0,-1,0,0, 0,0,1,0, 0,0,0,1}
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end

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

function Camera.setArenaTarget(side)
  if side=="player" or side=="enemy" then state.arenaTarget=side end
  return state.arenaTarget
end

function Camera.setArenaMode(mode)
  local count=#Camera.STADIUM.presets*2
  state.arenaMode=math.max(0,math.min(count,math.floor(tonumber(mode) or 0)))
  return state.arenaMode
end

function Camera.cycleArenaMode(delta)
  local count=#Camera.STADIUM.presets*2+1
  state.arenaMode=(state.arenaMode+(tonumber(delta) or 1))%count
  return state.arenaMode
end

function Camera.arenaModeLabel()
  if state.arenaMode==0 then return "FIELD" end
  local preset=math.floor((state.arenaMode-1)/2)
  local variant=(state.arenaMode%2==1) and "A" or "B"
  return ("SHOT %02d%s"):format(preset,variant)
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
  return math.max(0,math.pi/2-atan2(Camera.RIG.side,Camera.RIG.back))
end

local function axisSpan(beta,elevation)
  local c=math.cos(elevation)
  local horizontal=math.sin(beta)*c
  local vertical=math.sin(elevation)
  return math.sqrt(horizontal*horizontal+vertical*vertical)
end

local function spread()
  local rig=Camera.RIG
  local beta=atan2(rig.side,rig.back)
  local elevation=atan2(rig.height-rig.lookY,
    math.sqrt((rig.side-rig.lookX)^2+rig.back^2))
  local home=axisSpan(beta,elevation)
  if home<1e-6 then return 1 end
  return axisSpan(beta+state.orbit*orbitRange(),
    elevation+state.pitch*Camera.PITCH_RANGE)/home
end

local function stadiumActorMetrics(actor)
  local renderer=actor and actor.renderer
  if not (renderer and renderer.worldMetrics) then return 0,40 end
  local ok,metrics=pcall(renderer.worldMetrics,renderer)
  if not (ok and type(metrics)=="table") then return 0,40 end
  local actorScale=actor.scale and actor:scale() or 1
  local top=math.max(0,((tonumber(metrics.height) or 0)
    -(tonumber(metrics.floor) or 0))*actorScale)
  return top,math.max(40,(tonumber(metrics.radius) or 0)*actorScale,top*.5)
end

local function arenaFocus(opts)
  opts=opts or {}
  local actors=opts.actors or {}
  local playerTop=stadiumActorMetrics(actors.player)
  local enemyTop=stadiumActorMetrics(actors.enemy)
  local top=math.max(playerTop,enemyTop)
  -- Stadium derives camera anchors from each loaded model's bounds.  The
  -- overview keeps the field centre but raises its target for unusually tall
  -- battlers; ordinary models retain the ROM's 62-unit battle target.
  return {0,math.max(Camera.STADIUM.focus[2],top*.32),0}
end


local function arenaPresetPose(opts,groundY)
  local mode=state.arenaMode
  if mode==0 then return nil end
  local preset=Camera.STADIUM.presets[math.floor((mode-1)/2)+1]
  if not preset then return nil end
  local side=state.arenaTarget
  local actor=opts.actors and opts.actors[side]
  local slot,yaw=StadiumBattleLayout.slot(side,actor and actor.dex)
  local top,radius=stadiumActorMetrics(actor)
  local variant=(mode%2==1) and 0 or 3
  local pitch=preset[1+variant]*tau/65536
  local authoredYaw=preset[2+variant]
  local sideSign=side=="player" and 1 or -1
  yaw=yaw+authoredYaw*sideSign*tau/65536
  local distance=radius*preset[3+variant]
  local cp=math.cos(pitch)
  local focus={slot[1],groundY+math.max(20,top*.45),slot[3]}
  return {
    focus=focus,
    eye={focus[1]+math.sin(yaw)*cp*distance,
      focus[2]+math.sin(pitch)*distance,
      focus[3]+math.cos(yaw)*cp*distance},
    fov=math.rad(preset[7]),preset=math.floor((mode-1)/2),
    variant=variant==0 and "A" or "B",side=side,
  }
end

-- Arena-only Stadium field camera.  The legacy frame() below deliberately
-- remains untouched because it is calibrated to Gold's 160x144 HUD anchors.
function Camera.arenaFrame(width,height,opts)
  opts=opts or {}
  width=math.max(1,tonumber(width) or 1)
  height=math.max(1,tonumber(height) or 1)
  local sourceScale=math.max(1e-6,tonumber(opts.scale) or .05)
  local groundY=tonumber(opts.groundY) or 0
  local stadium=Camera.STADIUM
  local pose=arenaPresetPose(opts,groundY/sourceScale)
  local sourceFocus=pose and pose.focus or arenaFocus(opts)
  local focus={sourceFocus[1]*sourceScale,
    pose and sourceFocus[2]*sourceScale or groundY+sourceFocus[2]*sourceScale,
    sourceFocus[3]*sourceScale}
  local sourceEye=pose and pose.eye or stadium.eye
  local baseEye={sourceEye[1]*sourceScale,
    pose and sourceEye[2]*sourceScale or groundY+sourceEye[2]*sourceScale,
    sourceEye[3]*sourceScale}

  -- Viewer steering is an offset around Stadium's authored field shot.  A
  -- reset therefore returns to the game camera instead of the old Gold rig.
  local vx,vy,vz=baseEye[1]-focus[1],baseEye[2]-focus[2],baseEye[3]-focus[3]
  local radius=math.sqrt(vx*vx+vy*vy+vz*vz)*state.zoom
  local flat=math.sqrt(vx*vx+vz*vz)
  local yaw=atan2(vx,vz)-state.orbit*orbitRange()
  local elevation=atan2(vy,flat)+state.pitch*Camera.PITCH_RANGE
  elevation=math.min(elevation,math.rad(85))
  local cosElevation=math.cos(elevation)
  local ex=focus[1]+math.sin(yaw)*cosElevation*radius
  local eyeY=focus[2]+math.sin(elevation)*radius
  local ez=focus[3]+math.cos(yaw)*cosElevation*radius
  local view=Renderer.lookAt(ex,eyeY,ez,focus[1],focus[2],focus[3])
  local fov=pose and pose.fov or stadium.fov
  local projection=Renderer.matMul(LOVE_CANVAS_Y,Renderer.perspective(
    fov,width/height,stadium.near*sourceScale,stadium.far*sourceScale))
  local fit=Camera.fitScale(width,height)
  local ox,oy=Camera.fitOrigin(width,height,fit)
  return {
    view=view,projection=projection,vp=Renderer.matMul(projection,view),
    eye={ex,eyeY,ez},focus=focus,
    letterbox={lx=ox,ly=oy,scale=fit,pw=width,ph=height},
    stadium={fov=fov,near=stadium.near*sourceScale,
      far=stadium.far*sourceScale,sourceScale=sourceScale,
      mode=state.arenaMode,label=Camera.arenaModeLabel(),
      target=state.arenaTarget,preset=pose and pose.preset,
      variant=pose and pose.variant},
  }
end

function Camera.frame(width, height)
  -- Every owned battle scene enters through Camera.frame, including arena
  -- composition. Camera mods historically wrap this exported function to
  -- take camera authority. Keep the ROM-authored arena solve as the native
  -- answer inside that same seam so an external owner can call its captured
  -- provider frame, modify it, or yield without needing arena-specific code.
  local active=sceneFrameContext
  if active and active.arena==true then
    return Camera.arenaFrame(width,height,active)
  end
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
      local angle=math.min(atan2(vy,flat)+lift,math.rad(85))
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

-- Scene-only dispatcher. It deliberately invokes the current Camera.frame
-- field rather than a captured function: a camera mod may have replaced that
-- public seam after loading Stadium 2 Importer. The scoped context lets the
-- captured native frame return the correct classic/arena fallback and is
-- always restored, including when an external camera raises.
function Camera.sceneFrame(width,height,context)
  local previous=sceneFrameContext
  sceneFrameContext=type(context)=="table" and context or nil
  local result={pcall(Camera.frame,width,height)}
  sceneFrameContext=previous
  if not result[1] then error(result[2],0) end
  return result[2]
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
