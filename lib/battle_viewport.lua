-- Battle Art-style status placement for Stadium's native-looking HUD.
-- Portrait is not a separate dashboard: it keeps the 160x144 battle
-- composition, scales it by the engine's integer framebuffer fit, and makes
-- each detached status band one physical scale rung smaller.
local Viewport={}

local function displayDensity()
  if not (love and love.graphics and love.graphics.getDimensions
      and love.graphics.getPixelDimensions) then return 1 end
  local ok,w,h=pcall(love.graphics.getDimensions)
  local pok,pw,ph=pcall(love.graphics.getPixelDimensions)
  if not (ok and pok and tonumber(w) and tonumber(h)
      and tonumber(pw) and tonumber(ph) and w>0 and h>0) then return 1 end
  local dx,dy=pw/w,ph/h
  -- Stadium's camera/HUD transform is scalar. Equal-density axes are the
  -- normal mobile path; a forced-rotation backend with unequal axes keeps the
  -- conservative smaller density so nothing can overflow.
  return math.max(1e-6,math.min(dx,dy))
end

function Viewport.resolve(width,height)
  width=math.max(1,tonumber(width) or 1)
  height=math.max(1,tonumber(height) or 1)
  local portrait=height>width*1.20
  return {
    x=0,y=0,w=width,h=height,dpi=displayDensity(),
    orientation=portrait and "portrait" or "landscape",portrait=portrait,
  }
end

function Viewport.statusPanels(viewport,box,scale,enemyRect,playerRect)
  scale=math.max(.01,tonumber(scale) or 1)
  if not viewport.portrait then
    return {
      enemyX=viewport.x,enemyY=box.ly+enemyRect[2]*scale,
      playerX=viewport.x+viewport.w-playerRect[3]*scale,
      playerY=box.ly+playerRect[2]*scale,
      scale=scale,
    }
  end

  -- Battle Art's `max(1, fitScale - 1)`, expressed in LOVE units. One rung
  -- is 1/dpi here because the engine's fit scale is measured in framebuffer
  -- pixels while this compositor draws in density-independent coordinates.
  local rung=1/math.max(1e-6,viewport.dpi or 1)
  local hs=math.max(rung,scale-rung)
  return {
    -- Two authored pixels at the foe edge; the player card is flush right.
    enemyX=viewport.x+2*hs,
    enemyY=box.ly+enemyRect[2]*scale,
    playerX=viewport.x+viewport.w-playerRect[3]*hs,
    playerY=box.ly+playerRect[2]*scale,
    scale=hs,
  }
end

return Viewport
