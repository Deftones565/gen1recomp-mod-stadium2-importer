local Hud = { FROST=.55, TINT=.26, HEIGHT=72 }

-- Exact native Gold HUD spans.  Snap the RECT to the window edge and move the
-- full source band by the matching amount; moving a 160px band to x=0 leaves
-- the HUD's own eight-pixel inset visible and makes that inset grow with UI
-- scale.  These extents come straight from the coordinates used by
-- BattleState:drawHud / BattleHud:drawEnemyFrame / drawPlayerFrame.
Hud.HUD_RECT = {
  enemy = { 8, 0, 80, 32 },
  player = { 72, 56, 80, 40 },
}

-- AskGiveNicknameText opens Gold's ordinary 6x5 Yes/No window at (14,7).
-- Keep this as its own centred layer instead of letting it ride inside the
-- player HUD band: the wide compositor snaps that band to the far screen edge.
Hud.NICKNAME_MODAL_RECT = { 112, 56, 48, 40 }
local unpack = table.unpack or unpack

local frost, blurA, blurB, shader, gaugeShader, uiLayer, hudOnlyLayer, modalOnlyLayer
local fw, fh = 0, 0
local modRef = nil
local BLUR=[[
uniform vec2 dir;
vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){
 vec4 s=Texel(tex,tc)*.227027027;
 s+=(Texel(tex,tc+dir)+Texel(tex,tc-dir))*.194594595;
 s+=(Texel(tex,tc+2.*dir)+Texel(tex,tc-2.*dir))*.121621622;
 s+=(Texel(tex,tc+3.*dir)+Texel(tex,tc-3.*dir))*.054054054;
 s+=(Texel(tex,tc+4.*dir)+Texel(tex,tc-4.*dir))*.016216216;
 return s*color;
}]]

-- The cartridge HUD tiles carry opaque colour-zero paper. That is correct on
-- the Game Boy's flat white battle background, but becomes three conspicuous
-- white strips when those tiles are composited over our frosted battle cards.
-- Keep the key local to the fixed HP/EXP tile rows so white effects elsewhere
-- in the captured 160x144 layer remain opaque.
local GAUGE_PAPER = {
  { 8, 8, 16, 16 },    -- caught marker tile: keep the ball, drop its white paper
  { 16, 16, 88, 24 },  -- enemy HP label, channel, and end cap
  { 80, 72, 152, 80 }, -- player HP label, channel, and end cap
  { 80, 88, 144, 96 }, -- player EXP channel
}

local function gaugeCondition()
  local conditions = {}
  for i, region in ipairs(GAUGE_PAPER) do
    conditions[i] = ("(p.x>=%.1f&&p.x<%.1f&&p.y>=%.1f&&p.y<%.1f)")
      :format(region[1], region[3], region[2], region[4])
  end
  return table.concat(conditions, "||")
end

local GAUGE_KEY = ([=[
vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){
 vec4 pixel=Texel(tex,tc);
 vec2 p=tc*vec2(160.0,144.0);
 bool gauge=%s;
 if(gauge&&pixel.r>.94&&pixel.g>.94&&pixel.b>.94&&pixel.a>.94){
  return vec4(0.0);
 }
 return pixel*color;
}]=]):format(gaugeCondition())

local function release(v) if v and v.release then pcall(v.release,v) end end
local function canvas(w,h,filter)
  local ok,c=pcall(love.graphics.newCanvas,w,h,{format="rgba8",readable=true,dpiscale=1})
  if not ok then return nil end
  c:setFilter(filter or "linear",filter or "linear")
  return c
end

local function getShader()
  if shader == false then return nil end
  if not shader then
    local ok,value=pcall(love.graphics.newShader,BLUR)
    shader=ok and value or false
  end
  return shader or nil
end

local function getGaugeShader()
  if gaugeShader == false then return nil end
  if not gaugeShader then
    local ok,value=pcall(love.graphics.newShader,GAUGE_KEY)
    gaugeShader=ok and value or false
  end
  return gaugeShader or nil
end

-- Kept visible for the focused HUD regression test. The shader above applies
-- this same predicate in the final compositing pass.
function Hud.isGaugePaper(x,y,r,g,b,a)
  if (r or 0)<=.94 or (g or 0)<=.94 or (b or 0)<=.94 or (a or 1)<=.94 then
    return false
  end
  for _,region in ipairs(GAUGE_PAPER) do
    if x>=region[1] and x<region[3] and y>=region[2] and y<region[4] then
      return true
    end
  end
  return false
end

function Hud.build(source)
  if not source then return nil end
  local sw,sh=source:getDimensions()
  local h=Hud.HEIGHT
  local w=math.max(1,math.floor(sw*h/sh+.5))
  if not frost or fw~=w or fh~=h then
    release(frost);release(blurA);release(blurB)
    frost,blurA,blurB=canvas(w,h),canvas(w,h),canvas(w,h)
    fw,fh=w,h
  end
  if not (frost and blurA and blurB) then return nil end
  local g=love.graphics
  local previous=g.getCanvas and {g.getCanvas()} or nil
  local oldShader=g.getShader and g.getShader() or nil
  local oldBlend,oldAlpha=g.getBlendMode()
  local min,mag=source:getFilter();source:setFilter("linear","linear")
  local ok=pcall(function()
    g.setBlendMode("replace","premultiplied");g.setColor(1,1,1,1)
    g.setCanvas(frost);g.clear(0,0,0,0);g.draw(source,0,0,0,w/sw,h/sh)
    local blur=getShader()
    if blur then
      g.setShader(blur);g.setCanvas(blurA);g.clear(0,0,0,0)
      blur:send("dir",{2.5/w,0});g.draw(frost)
      g.setCanvas(blurB);g.clear(0,0,0,0)
      blur:send("dir",{0,2.5/h});g.draw(blurA)
      frost,blurB=blurB,frost
    end
  end)
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  g.setShader(oldShader);g.setBlendMode(oldBlend or "alpha",oldAlpha)
  source:setFilter(min or "nearest",mag or "nearest")
  return ok and frost or nil
end

local function keyedPaperRect(x,y,w,h)
  local yesNo=(y==56 and h==40 and w==48 and (x==8 or x==112))
  return (x==0 and y==0 and w==160 and h==144)
    or (x==0 and y==96 and w==160 and h==48)
    or (x==64 and y==96 and w==96 and h==48)
    or (x==16 and y==96 and w==144 and h==48)
    or yesNo
end

-- Exposed for the headless layout regression. All native Yes/No paper is
-- removed: the compositor supplies the same frosted backing as the HUD.
function Hud.keysPaperRect(x,y,w,h)
  return keyedPaperRect(x,y,w,h)
end

function Hud.layer(draw,opts)
  if not uiLayer then uiLayer=canvas(160,144,"nearest") end
  if not uiLayer then return nil end
  local g=love.graphics
  local previous=g.getCanvas and {g.getCanvas()} or nil
  local oldBlend,oldAlpha=g.getBlendMode()
  local rectangle=g.rectangle
  local ok,err=pcall(function()
    g.setCanvas(uiLayer);g.clear(0,0,0,0);g.setBlendMode("alpha","alphamultiply")
    -- Gold's paper is the only opaque part being replaced. Borders, glyphs,
    -- bars, sprites and animation objects still draw normally.
    g.rectangle=function(mode,x,y,w,h,...)
      local r,gg,b,a=g.getColor()
      local paper=keyedPaperRect(x,y,w,h)
      if mode=="fill" and paper and r>.94 and gg>.94 and b>.94
          and (a or 1)>.94 then return end
      return rectangle(mode,x,y,w,h,...)
    end
    draw()
  end)
  g.rectangle=rectangle
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  g.setBlendMode(oldBlend or "alpha",oldAlpha);g.setColor(1,1,1,1)
  if not ok then error(err,0) end
  return uiLayer
end

-- The reference wide compositor keeps the status HUD separate from the battle
-- text/window layer before snapping it to the display edges.  Gen 2 needs the same split
-- for AskNickname: drawHud contains the native status blocks, while drawScene
-- also contains the centred Yes/No modal.  A second transparent capture lets
-- the two keep independent destinations without reimplementing Gold's HUD.
function Hud.hudLayer(draw)
  if not hudOnlyLayer then hudOnlyLayer=canvas(160,144,"nearest") end
  if not hudOnlyLayer then return nil end
  local g=love.graphics
  local previous=g.getCanvas and {g.getCanvas()} or nil
  local oldBlend,oldAlpha=g.getBlendMode()
  local oldShader=g.getShader and g.getShader() or nil
  local ok,err=pcall(function()
    g.setCanvas(hudOnlyLayer)
    g.clear(0,0,0,0)
    g.setBlendMode("alpha","alphamultiply")
    g.setShader()
    draw()
  end)
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  g.setShader(oldShader)
  g.setBlendMode(oldBlend or "alpha",oldAlpha)
  g.setColor(1,1,1,1)
  if not ok then error(err,0) end
  return hudOnlyLayer
end

-- AskNickname's Yes/No box is drawn by Gold after drawHud(), directly on top
-- of the native player HUD.  Once the box's white paper is keyed transparent,
-- capturing that finished frame also captures the old HUD *behind* the box.
-- A destination restore cannot remove pixels already baked into the source.
-- Keep a third source texture whose caller suppresses drawHud(): it contains
-- the modal border/text/cursor and no status HUD underneath it.
function Hud.modalLayer(draw)
  if not modalOnlyLayer then modalOnlyLayer=canvas(160,144,"nearest") end
  if not modalOnlyLayer then return nil end
  local g=love.graphics
  local previous=g.getCanvas and {g.getCanvas()} or nil
  local oldBlend,oldAlpha=g.getBlendMode()
  local oldShader=g.getShader and g.getShader() or nil
  local rectangle=g.rectangle
  local ok,err=pcall(function()
    g.setCanvas(modalOnlyLayer)
    g.clear(0,0,0,0)
    g.setBlendMode("alpha","alphamultiply")
    g.setShader()
    -- Same paper key as Hud.layer: remove Chrome.clear and the Yes/No fill,
    -- while preserving Gold's border, cursor and text.
    g.rectangle=function(mode,x,y,w,h,...)
      local r,gg,b,a=g.getColor()
      local paper=keyedPaperRect(x,y,w,h)
      if mode=="fill" and paper and r>.94 and gg>.94 and b>.94
          and (a or 1)>.94 then return end
      return rectangle(mode,x,y,w,h,...)
    end
    draw()
  end)
  g.rectangle=rectangle
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  g.setShader(oldShader)
  g.setBlendMode(oldBlend or "alpha",oldAlpha)
  g.setColor(1,1,1,1)
  if not ok then error(err,0) end
  return modalOnlyLayer
end

local function panel(scene,rect)
  -- DRAW HUD PANELS option: when OFF, suppress the frosted/tinted backing
  -- glass entirely. The status cards and lower band still composite their HUD
  -- text onto the raw 3D scene, just without the plate behind them.
  if modRef and modRef.options then
    local ok,enabled=pcall(modRef.options.get,modRef.options,"stadium2_hud_panels")
    if ok and enabled==false then return true end
  end
  if not (scene and scene.width and scene.height) then return false end
  local g=love.graphics
  local x,y,w,h=rect[1],rect[2],rect[3],rect[4]
  if not frost then
    g.setColor(1,1,1,.78);g.rectangle("fill",x,y,w,h)
    g.setColor(1,1,1,1)
    return true
  end
  local qx,qy=x*fw/scene.width,y*fh/scene.height
  local qw,qh=math.max(1,w*fw/scene.width),math.max(1,h*fh/scene.height)
  local quad=g.newQuad(qx,qy,qw,qh,fw,fh)
  g.setColor(1,1,1,Hud.FROST);g.draw(frost,quad,x,y,0,w/qw,h/qh)
  g.setColor(1,1,1,Hud.TINT);g.rectangle("fill",x,y,w,h)
  g.setColor(1,1,1,1)
  return true
end

-- Capture the mod handle so panel() can read the DRAW HUD PANELS option live.
function Hud.configure(mod)
  modRef = mod
end

function Hud.layout(scene,screen)
  if not (scene and screen and scene.hudBox) then return nil end
  local box=scene.hudBox
  local s=box.scale
  -- Yes/No windows occupy the same native rows as the player HUD.  AskNickname
  -- is separated into its own centred modal layer, so its status bands can
  -- stay snapped exactly where the wide battle put them.
  local asking=screen.phase=="ask-nickname" or screen.phase=="ask-forget"
    or screen.phase=="stop-learning" or screen.phase=="ask-shift"
  local modal=asking and (screen.messageTimer or 0)<=0
  local nicknameModal=screen.phase=="ask-nickname" and modal
  -- AskNickname follows the reference wide compositor: status HUDs
  -- remain snapped, while the modal is a separate centred native layer.
  -- Other legacy Yes/No states retain the old joined-band fallback for now.
  local snap=(not modal or nicknameModal)
    and not screen.showEnemyTrainer and not screen.showPlayerTrainer
  local er,pr=Hud.HUD_RECT.enemy,Hud.HUD_RECT.player
  -- Same snap geometry as the established wide battle compositor: the
  -- rectangle itself touches the edge, while the full 160px source band is
  -- offset by that rectangle's native x inset.
  local enemyX=snap and (-er[1]*s) or box.lx
  local playerX=snap and (scene.width-(pr[1]+pr[3])*s) or box.lx
  return {
    box=box, scale=s, asking=asking, modal=modal,
    nicknameModal=nicknameModal, snap=snap,
    enemyX=enemyX, playerX=playerX,
    enemyPanelX=snap and 0 or (box.lx+er[1]*s),
    playerPanelX=snap and (scene.width-pr[3]*s) or (box.lx+pr[1]*s),
  }
end

-- Put a rectangle of the clean 3D scene back over already-composited HUD.
-- A translucent glass panel cannot hide glyphs that were drawn beneath it;
-- restoring the pristine scene first is what makes the modal genuinely glass
-- rather than a ghosted HUD with a blur painted over the top.
local function restoreSceneRect(scene,rect)
  local source=scene and (scene.presentCanvas or scene.canvas)
  if not (source and source.getDimensions and scene.width and scene.height) then
    return false
  end
  local g=love.graphics
  local sw,sh=source:getDimensions()
  if sw<=0 or sh<=0 or scene.width<=0 or scene.height<=0 then return false end
  local x,y,w,h=rect[1],rect[2],rect[3],rect[4]
  local qx=x*sw/scene.width
  local qy=y*sh/scene.height
  local qw=w*sw/scene.width
  local qh=h*sh/scene.height
  local quad=g.newQuad(qx,qy,qw,qh,sw,sh)
  g.setColor(1,1,1,1)
  g.draw(source,quad,x,y,0,w/qw,h/qh)
  return true
end

function Hud.composite(scene,screen,layer,hudLayer,modalLayer)
  if not (scene and layer and scene.hudBox) then return false end
  local g=love.graphics
  local layout=Hud.layout(scene,screen)
  local box,s=layout.box,layout.scale
  -- The detached Stadium HUD follows REAL battle visibility only.  Do not
  -- inherit BattleAnimClearHud here: that flag exists to blank the attacker's
  -- native BG HUD while a 2D move animation owns those tiles.  Detached
  -- snapped status cards are outside that animation layer and stay visible.
  local enemyLive=screen.showEnemyHud and not screen.showEnemyTrainer
  local playerLive=screen.showPlayerHud and not screen.showPlayerTrainer
    and not screen.tutorial
  local ex,px=layout.enemyX,layout.playerX
  local er,pr=Hud.HUD_RECT.enemy,Hud.HUD_RECT.player
  if enemyLive then
    panel(scene,{layout.enemyPanelX,box.ly+er[2]*s,er[3]*s,er[4]*s})
  end
  if playerLive then
    panel(scene,{layout.playerPanelX,box.ly+pr[2]*s,pr[3]*s,pr[4]*s})
  end
  panel(scene,{box.lx,box.ly+96*s,160*s,48*s})
  g.setColor(1,1,1,1)
  local oldShader=g.getShader and g.getShader() or nil
  local key=getGaugeShader()
  if key then g.setShader(key) end
  local enemy=g.newQuad(0,0,160,48,160,144)
  local player=g.newQuad(0,48,160,48,160,144)
  local lower=g.newQuad(0,96,160,48,160,144)
  -- A snapped Stadium HUD is ALWAYS sourced from the independent HUD capture,
  -- not from the native battle scene.  Besides keeping AskNickname out of the
  -- player band, this is what prevents Gold's per-move BattleAnimClearHud from
  -- making a status card blink off for the duration of an attack.
  local upper=(layout.snap and hudLayer) or layer
  g.draw(upper,enemy,ex,box.ly,0,s,s)
  g.draw(upper,player,px,box.ly+48*s,0,s,s)
  g.draw(layer,lower,box.lx,box.ly+96*s,0,s,s)
  if key then g.setShader(oldShader) end

  -- Native Yes/No windows use the same frosted-glass treatment as the HUD.
  -- They can overlap a snapped status band, so first restore the clean 3D
  -- scene under the modal, then lay the frost/tint, then draw Gold's own
  -- border/text/cursor with its white paper already keyed out of `layer`.
  -- This is intentionally after the gauge-key shader is removed: the nickname
  -- rectangle occupies the player HP/EXP source rows and must not inherit that
  -- tile-specific key.
  if layout.asking and layout.modal then
    local left=screen.phase=="ask-shift" and 8 or 112
    local r={left,56,48,40}
    local target={box.lx+r[1]*s,box.ly+r[2]*s,r[3]*s,r[4]*s}
    restoreSceneRect(scene,target)
    panel(scene,target)
    local modalQuad=g.newQuad(r[1],r[2],r[3],r[4],160,144)
    g.setColor(1,1,1,1)
    -- AskNickname uses the clean modal-only capture; other legacy Yes/No
    -- states still fall back to the full native layer until they are split too.
    g.draw((layout.nicknameModal and modalLayer) or layer,modalQuad,
      target[1],target[2],0,s,s)
  end
  return true
end

Hud.panel = panel
Hud.restoreSceneRect = restoreSceneRect
Hud.gaugeShader = getGaugeShader

function Hud.invalidate()
  release(frost);release(blurA);release(blurB);release(gaugeShader)
  release(uiLayer);release(hudOnlyLayer);release(modalOnlyLayer)
  frost,blurA,blurB,gaugeShader,uiLayer,hudOnlyLayer,modalOnlyLayer=
    nil,nil,nil,nil,nil,nil,nil
  fw,fh=0,0
end

return Hud
