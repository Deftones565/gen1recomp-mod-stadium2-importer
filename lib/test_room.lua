-- In-game test room (a mod tool the user asked for; not part of Stadium 2).
-- It shows the same battle scene, actors and move-effect adapter that real
-- battles use, so the graphics options (EXTRA EFFECTS, POKE BALL, 3D
-- RESOLUTION, ...) apply here exactly as in a battle.
--
-- Opening it pushes a blocking state (the game underneath stops taking
-- input) and takes over LOVE's draw and input callbacks; closing restores
-- them and pops the state, returning control to the game. Controls work by
-- touch, mouse, keyboard and gamepad, and the layout scales to the window.
local Presentation=require("mods.STADIUM2_IMPORTER.lib.battle_presentation")
local Camera=require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Sequence=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local Environment=require("mods.STADIUM2_IMPORTER.lib.battle_environment")
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local ArenaRuntime=require("mods.STADIUM2_IMPORTER.lib.arena_runtime")

local Room={}
Room.__index=Room

local FX_COUNT=301 -- 1..251 moves, 252..301 non-move battle effects
-- Classic, the Kenney scenes, then every Stadium arena (needs the Stadium 2
-- ROM the game imported from; a failure is shown and Classic is used).
local SCENES={{"CLASSIC",nil},{"WOODLAND","grass"},{"CAVE","cave"},
  {"FRESHWATER","freshwater"},{"TOWN","town"},{"OCEAN","ocean"},{"MOUNTAIN","mountain"},{"ICE CAVE","ice_cave"},{"CAVE WATER","cave_water"},{"INDOOR WATER","indoor_water"},{"INTERIOR","interior"},{"INDUSTRIAL","industrial"},{"RUINS","ruins"},{"SHIP","ship"},{"GYM","gym"},{"LEAGUE","league"}}
do
  local names={'FALKNER','BUGSY','WHITNEY','MORTY','JASMINE','CHUCK','PRYCE','CLAIR',
    'TEAM ROCKET','WILL','KOGA','BRUNO','KAREN','CHAMPION','BROCK','MISTY','LT. SURGE',
    'ERIKA','JANINE','SABRINA','BLAINE','BLUE','RED'}
  names[27]='BATTLE TOWER';names[28]='INDOOR';names[29]='FREE BATTLE PARK';names[30]='RIVAL'
  for index=0,(tonumber(ArenaRuntime.COUNT) or 0)-1 do
    SCENES[#SCENES+1]={("ARENA %02d%s"):format(index,names[index+1] and (" "..names[index+1]) or ""),
      nil,index}
  end
end
local TIMES={"DAY","EVE","NITE"}
local CALLBACKS={"draw","update","keypressed","keyreleased","textinput",
  "mousepressed","mousereleased","mousemoved","wheelmoved","touchpressed",
  "touchmoved","touchreleased","gamepadpressed","gamepadreleased",
  "gamepadaxis","joystickpressed","joystickreleased","joystickhat",
  "joystickaxis"}
-- Releases also reach the game, so nothing it saw pressed stays held.
local FORWARD={keyreleased=true,mousereleased=true,touchreleased=true,
  gamepadreleased=true,joystickreleased=true}
local REPEAT_DELAY,REPEAT_RATE=.4,.09

local current -- the open room

local function wrap(value,count) return (value-1)%count+1 end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

-- Names come from the running game's data; missing ones fall back to numbers.
local function nameTables(game)
  local species,moves={},{}
  local data=game and game.data or {}
  for key,def in pairs(type(data.pokemon)=="table" and data.pokemon or {}) do
    local dex=type(def)=="table" and tonumber(def.dex)
    if dex then species[dex]=tostring(def.name or key) end
  end
  for key,def in pairs(type(data.moves)=="table" and data.moves or {}) do
    local index=type(def)=="table" and tonumber(def.index or def.number)
    if index then moves[index]=tostring(def.name or key):gsub("_"," ") end
  end
  for key,value in pairs(Sequence) do
    local name=type(key)=="string" and key:match("^(.-)_ENTRY$")
    if name and type(value)=="number" and value>251 and value<=FX_COUNT then
      moves[value]=name:gsub("_"," ")
    end
  end
  return species,moves
end

function Room.new(game)
  local self=setmetatable({game=game,side="player",fx=1,sceneIndex=1,
    timeIndex=1,paused=false,uiHidden=false,touches={},buttons={},
    notes={},fonts={},heldRepeat=nil},Room)
  self.speciesNames,self.moveNames=nameTables(game)
  local count=tonumber(Importer.COUNT and Importer.COUNT()) or 251
  self.speciesCount=clamp(math.floor(count),1,251)
  self.dex={player=math.min(7,self.speciesCount),enemy=math.min(1,self.speciesCount)}
  -- Start on a move the source can use; Surf when it exists (57).
  self.fx=57
  return self
end

function Room:note(message)
  self.message=tostring(message)
  self.messageTime=4
end

function Room:environmentSelection()
  local id=SCENES[self.sceneIndex][2]
  if not id then return {mode="classic",id="classic"} end
  local ok,selection=pcall(Environment.select,nil,"kenney",false,nil,id)
  if ok and type(selection)=="table" and selection.mode=="environment" then return selection end
  return {mode="classic",id="classic"}
end

function Room:buildScene()
  if self.scene then self.scene:release();self.scene,self.adapter=nil,nil end
  self.error=nil
  if not (Importer.available and Importer.available()) then
    self.error="Stadium 2 models are not imported for this save yet.\nLoad a save and finish the import first."
    return false
  end
  -- The room always plays effects, even with MOVE EFFECTS off in battles.
  local importer=setmetatable({betaBattleFxEnabled=function() return true end},{__index=Importer})
  local adapter,err=Adapter.new(importer,{warn=function(d)
    self:note(type(d)=="table" and (d.message or d.code) or d)
  end})
  if not adapter and err then self:note("move effects unavailable: "..tostring(err)) end
  local arena
  local arenaIndex=SCENES[self.sceneIndex][3]
  if arenaIndex then
    local err
    arena,err=ArenaRuntime.load(arenaIndex,Importer)
    if not arena then self:note("arena unavailable, showing Classic: "..tostring(err)) end
  end
  self.arenaIndex=arena and arenaIndex or nil
  local scene=Presentation.newScene({label="Stadium 2 test room",battleFx=adapter,
    arena=arena,arenaMode=arena~=nil,warn=function(message) self:note(message) end})
  scene.game={world={map={def={environment="TOWN"}},clockHour=12,daytime=TIMES[self.timeIndex]}}
  scene.environmentSelection=self:environmentSelection()
  for _,side in ipairs({"enemy","player"}) do
    local dex=self.dex[side]
    if not Presentation.setBattler(scene,side,nil,{species=dex},dex) then
      self:note(("model %03d could not be loaded"):format(dex))
    end
  end
  if adapter then
    adapter.onImpact=function(target,_,moveId)
      local actor=scene.actors[target]
      if not (actor and actor.hit) then return false,"no defender actor" end
      return actor:hit(moveId)
    end
  end
  self.scene,self.adapter=scene,adapter
  return true
end

function Room:play()
  local scene,adapter=self.scene,self.adapter
  if not (scene and adapter) then return end
  if adapter.player and adapter.player.abortAll then pcall(adapter.player.abortAll,adapter.player) end
  local side=self.side
  local target=side=="player" and "enemy" or "player"
  local actor=scene.actors[side]
  if self.fx<=251 then
    local ok,reason=false,"no model"
    if actor and actor.attack then ok,reason=actor:attack(self.fx,true) end
    if not ok then self:note("no move animation: "..tostring(reason)) end
    local okFx,err=pcall(adapter.playMoveAndImpact,adapter,self.fx,side,actor,nil,scene.actors[target])
    if not okFx then self:note(err) end
  else
    local okFx,effect,err=pcall(adapter.signalEffect,adapter,self.fx,side)
    if not okFx then self:note(effect)
    elseif not effect then self:note(err or "effect is turned off in GRAPHICS") end
  end
end

function Room:fxLabel()
  local name=self.moveNames[self.fx]
  local kind=self.fx<=251 and "MOVE" or "FX"
  return ("%s %03d %s"):format(kind,self.fx,name or "")
end

function Room:speciesLabel(side)
  local dex=self.dex[side]
  return ("#%03d %s"):format(dex,self.speciesNames[dex] or "")
end

-- ---------------------------------------------------------------- actions
function Room:stepFx(delta) self.fx=wrap(self.fx+delta,FX_COUNT);self:play() end
function Room:stepSpecies(delta)
  local side=self.side
  self.dex[side]=wrap(self.dex[side]+delta,self.speciesCount)
  if self.scene then Presentation.setBattler(self.scene,side,nil,{species=self.dex[side]},self.dex[side]) end
end
function Room:swapSide() self.side=self.side=="player" and "enemy" or "player" end
function Room:stepScene(delta)
  self.sceneIndex=wrap(self.sceneIndex+delta,#SCENES)
  -- Arenas are loaded with the scene; Classic and Kenney scenes switch live.
  if SCENES[self.sceneIndex][3] or self.arenaIndex then
    self:buildScene()
  elseif self.scene then
    self.scene.environmentSelection=self:environmentSelection()
  end
end
function Room:stepTime()
  self.timeIndex=wrap(self.timeIndex+1,#TIMES)
  if self.scene then self.scene.game.world.daytime=TIMES[self.timeIndex] end
end

-- ---------------------------------------------------------------- layout
function Room:font(size)
  size=math.max(8,math.floor(size))
  local font=self.fonts[size]
  if not font then font=love.graphics.newFont(size);self.fonts[size]=font end
  return font
end

function Room:layout(w,h)
  local handheld=love.system and love.system.getOS
    and (love.system.getOS()=="Android" or love.system.getOS()=="iOS")
  local base=math.min(w,h)
  local u=math.floor(clamp(base/(handheld and 8 or 10),40,handheld and 150 or 72))
  local pad=math.floor(u*.18)
  local buttons={}
  local function button(x,y,bw,bh,label,action,options)
    options=options or {}
    buttons[#buttons+1]={x=x,y=y,w=bw,h=bh,label=label,action=action,
      rep=options.rep,kind=options.kind,id=options.id or label}
  end
  -- Top bar: exit, status, pause and hide.
  local th=math.floor(u*.8)
  button(pad,pad,math.floor(u*1.8),th,"EXIT",function() self:close() end,{kind="exit"})
  button(w-pad-math.floor(u*1.8),pad,math.floor(u*1.8),th,self.paused and "RESUME" or "PAUSE",
    function() self.paused=not self.paused end)
  button(w-2*pad-math.floor(u*3.4),pad,math.floor(u*1.6),th,self.uiHidden and "SHOW" or "HIDE",
    function() self.uiHidden=not self.uiHidden end)
  self.topBottom=pad+th
  self.unit,self.pad=u,pad
  if self.uiHidden or self.error then self.buttons=buttons;self.panelTop=h;return end

  local function row(x,y,rw,parts)
    -- parts: {label, action, weight, options}; widths share rw by weight.
    local total=0
    for _,p in ipairs(parts) do total=total+p[3] end
    local cx=x
    local free=rw-pad*(#parts-1)
    for i,p in ipairs(parts) do
      local bw=i==#parts and (x+rw-cx) or math.floor(free*p[3]/total)
      button(cx,y,bw,u,p[1],p[2],p[4])
      cx=cx+bw+pad
    end
  end
  local moveRow={{"<",function() self:stepFx(-1) end,1,{rep=true,id="fx-"}},
    {self:fxLabel(),function() self:play() end,5,{kind="label",id="fx"}},
    {">",function() self:stepFx(1) end,1,{rep=true,id="fx+"}},
    {"PLAY",function() self:play() end,1.8,{kind="accent"}}}
  local speciesRow={{self.side=="player" and "YOURS" or "FOE",function() self:swapSide() end,1.8},
    {"<",function() self:stepSpecies(-1) end,1,{rep=true,id="sp-"}},
    {self:speciesLabel(self.side),nil,5,{kind="label",id="sp"}},
    {">",function() self:stepSpecies(1) end,1,{rep=true,id="sp+"}}}
  local sceneRow={{"<",function() self:stepScene(-1) end,1,{id="sc-"}},
    {SCENES[self.sceneIndex][1],nil,5,{kind="label",id="sc"}},
    {">",function() self:stepScene(1) end,1,{id="sc+"}},
    {TIMES[self.timeIndex],function() self:stepTime() end,1.8}}
  local landscape=w>h*1.25 and w-3*pad>=2*u*7
  if landscape then
    local rw=math.floor(math.min((w-3*pad)/2,u*11))
    local left=math.floor((w-(2*rw+pad))/2)
    local y2=h-pad-u
    local y1=y2-pad-u
    row(left,y1,rw,moveRow)
    row(left,y2,rw,speciesRow)
    row(left+rw+pad,y2,rw,sceneRow)
    self.panelTop=y1
    self.infoBox={left+rw+pad,y1,rw,u}
  else
    local rw=math.floor(math.min(w-2*pad,u*11))
    local left=math.floor((w-rw)/2)
    local y3=h-pad-u
    local y2=y3-pad-u
    local y1=y2-pad-u
    row(left,y1,rw,moveRow)
    row(left,y2,rw,speciesRow)
    row(left,y3,rw,sceneRow)
    self.panelTop=y1
    self.infoBox={left,y1-pad-math.floor(u*.9),rw,math.floor(u*.9)}
  end
  self.buttons=buttons
end

-- ---------------------------------------------------------------- frame
function Room:update(dt)
  if self.messageTime then
    self.messageTime=self.messageTime-dt
    if self.messageTime<=0 then self.message,self.messageTime=nil,nil end
  end
  local held=self.heldRepeat
  if held then
    held.timer=held.timer-dt
    while held.timer<=0 do held.timer=held.timer+REPEAT_RATE;held.button.action() end
  end
  local scene=self.scene
  if not scene then return end
  if not self.paused then
    Camera.update(dt)
    for _,actor in pairs(scene.actors or {}) do actor:update(dt) end
    scene:stepArena(dt)
    scene:updateBattleFx(dt)
  end
  local ok=scene:render()
  if not ok and scene.defect then self:note(scene.defect) end
end

local function colors(kind,pressed)
  if kind=="exit" then return pressed and {.75,.2,.2,.95} or {.55,.12,.12,.88} end
  if kind=="accent" then return pressed and {.3,.6,1,.95} or {.16,.42,.85,.9} end
  if kind=="label" then return pressed and {.25,.25,.3,.9} or {.08,.08,.1,.78} end
  return pressed and {.35,.35,.42,.95} or {.16,.16,.2,.85}
end

function Room:draw()
  local g=love.graphics
  local w,h=g.getDimensions()
  self:layout(w,h)
  g.push("all")
  g.origin();g.setCanvas();g.setShader();g.setScissor()
  g.clear(.05,.05,.07,1)
  local canvas=self.scene and self.scene.presentCanvas
  if canvas then
    local cw,ch=canvas:getDimensions()
    g.setColor(1,1,1,1)
    g.draw(canvas,0,0,0,w/cw,h/ch)
  end
  local u,pad=self.unit,self.pad
  local radius=math.floor(u*.18)
  -- Status line in the top bar.
  local font=self:font(u*.34)
  g.setFont(font)
  local fps=love.timer and love.timer.getFPS and love.timer.getFPS() or 0
  local status=("TEST ROOM  %d FPS"):format(fps)
  local sx=pad+math.floor(u*1.8)+pad
  local sw=w-sx-(2*pad+math.floor(u*3.4))-pad
  if sw>font:getWidth("TEST ROOM")+pad then
    g.setColor(0,0,0,.55)
    g.rectangle("fill",sx,pad,sw,math.floor(u*.8),radius,radius)
    g.setColor(1,1,1,1)
    g.printf(status,sx,pad+math.floor((u*.8-font:getHeight())/2),sw,"center")
  end
  if self.error then
    local ew=math.min(w-2*pad,u*12)
    local ex=(w-ew)/2
    local lines=select(2,font:getWrap(self.error,ew-2*pad))
    local eh=#lines*font:getHeight()+2*pad
    g.setColor(0,0,0,.8);g.rectangle("fill",ex,h/2-eh/2,ew,eh,radius,radius)
    g.setColor(1,1,1,1);g.printf(self.error,ex+pad,h/2-eh/2+pad,ew-2*pad,"center")
  end
  -- Info line: last note (errors, skipped animations).
  if self.infoBox and not self.uiHidden and not self.error then
    local x,y,bw,bh=unpack(self.infoBox)
    local text=self.message or "Drag to turn the camera. Pinch or scroll to zoom."
    local small=self:font(u*.28)
    g.setFont(small)
    g.setColor(0,0,0,.6);g.rectangle("fill",x,y,bw,bh,radius,radius)
    g.setColor(1,1,1,self.message and 1 or .75)
    local _,wrapped=small:getWrap(text,bw-2*pad)
    local shown=math.max(1,math.min(#wrapped,math.floor((bh-pad)/small:getHeight())))
    local ty=y+math.floor((bh-shown*small:getHeight())/2)
    for i=1,shown do g.printf(wrapped[i],x+pad,ty+(i-1)*small:getHeight(),bw-2*pad,"left") end
  end
  -- Buttons.
  for _,b in ipairs(self.buttons) do
    local pressed=self.pressedId==b.id
    g.setColor(colors(b.kind,pressed))
    g.rectangle("fill",b.x,b.y,b.w,b.h,radius,radius)
    g.setColor(1,1,1,.18);g.setLineWidth(math.max(1,u/40))
    g.rectangle("line",b.x+.5,b.y+.5,b.w-1,b.h-1,radius,radius)
    local size=u*(b.kind=="label" and .36 or .4)
    local f=self:font(size)
    while f:getWidth(b.label)>b.w-pad and size>9 do size=size-2;f=self:font(size) end
    g.setFont(f);g.setColor(1,1,1,1)
    g.printf(b.label,b.x,b.y+math.floor((b.h-f:getHeight())/2),b.w,"center")
  end
  g.pop()
end

-- ---------------------------------------------------------------- input
function Room:buttonAt(x,y)
  for i=#self.buttons,1,-1 do
    local b=self.buttons[i]
    if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then return b end
  end
end

function Room:pointerPressed(id,x,y)
  local b=self:buttonAt(x,y)
  if b and b.action then
    self.pressedId,self.pressedPointer=b.id,id
    if b.rep then
      b.action()
      self.heldRepeat={button=b,timer=REPEAT_DELAY,pointer=id}
    end
    return
  end
  if b then return end -- labels without actions swallow the touch
  self.touches[id]={x=x,y=y}
end

function Room:pointerMoved(id,x,y,dx,dy)
  local t=self.touches[id]
  if not t then return end
  local count=0
  for _ in pairs(self.touches) do count=count+1 end
  local w=love.graphics.getWidth()
  if count>=2 then
    -- Pinch: compare the two touch distances before and after this move.
    local other
    for key,value in pairs(self.touches) do if key~=id then other=value end end
    local before=math.sqrt((t.x-other.x)^2+(t.y-other.y)^2)
    local after=math.sqrt((x-other.x)^2+(y-other.y)^2)
    if before>1 and after>1 then Camera.zoom(before/after) end
  else
    Camera.mouseOrbit(dx*1280/w)
    Camera.mousePitch(dy*1280/w)
  end
  t.x,t.y=x,y
end

function Room:pointerReleased(id,x,y)
  self.touches[id]=nil
  if self.heldRepeat and self.heldRepeat.pointer==id then self.heldRepeat=nil end
  if self.pressedPointer~=id then return end
  local pressedId=self.pressedId
  self.pressedId,self.pressedPointer=nil,nil
  local b=self:buttonAt(x,y)
  if b and b.id==pressedId and b.action and not b.rep then b.action() end
end

local KEYS={
  escape=function(self) self:close() end,
  backspace=function(self) self:close() end,
  left=function(self) self:stepFx(-1) end,
  right=function(self) self:stepFx(1) end,
  up=function(self) self:stepSpecies(1) end,
  down=function(self) self:stepSpecies(-1) end,
  ["return"]=function(self) self:play() end,
  space=function(self) self:play() end,
  tab=function(self) self:swapSide() end,
  p=function(self) self.paused=not self.paused end,
  h=function(self) self.uiHidden=not self.uiHidden end,
  pageup=function(self) self:stepScene(-1) end,
  pagedown=function(self) self:stepScene(1) end,
  t=function(self) self:stepTime() end,
}
local PAD={
  b=KEYS.escape,back=KEYS.escape,
  dpleft=KEYS.left,dpright=KEYS.right,dpup=KEYS.up,dpdown=KEYS.down,
  a=KEYS.space,x=KEYS.tab,y=KEYS.pagedown,start=KEYS.p,
  leftshoulder=function(self) self:stepFx(-10) end,
  rightshoulder=function(self) self:stepFx(10) end,
}

function Room:handlers()
  local room=self
  return {
    draw=function() room:draw() end,
    update=function(dt) room:update(dt) end,
    keypressed=function(key)
      local fn=KEYS[key]
      if fn then fn(room) end
    end,
    gamepadpressed=function(_,button)
      local fn=PAD[button]
      if fn then fn(room) end
    end,
    mousepressed=function(x,y,button,istouch)
      if istouch or button~=1 then return end
      room:pointerPressed("mouse",x,y)
    end,
    mousemoved=function(x,y,dx,dy,istouch)
      if istouch then return end
      room:pointerMoved("mouse",x,y,dx,dy)
    end,
    mousereleased=function(x,y,button,istouch)
      if istouch or button~=1 then return end
      room:pointerReleased("mouse",x,y)
    end,
    wheelmoved=function(_,y) if y~=0 then Camera.stepZoom(y) end end,
    touchpressed=function(id,x,y) room:pointerPressed(id,x,y) end,
    touchmoved=function(id,x,y,dx,dy) room:pointerMoved(id,x,y,dx,dy) end,
    touchreleased=function(id,x,y) room:pointerReleased(id,x,y) end,
  }
end

-- ---------------------------------------------------------------- open/close
function Room:install()
  local mine=self:handlers()
  self.saved={}
  for _,name in ipairs(CALLBACKS) do
    local original=love[name]
    self.saved[name]={value=original}
    local handler=mine[name]
    if name=="update" then
      -- The game keeps its clock, audio and blocking state running.
      love.update=function(dt)
        if original then original(dt) end
        if current==self then handler(dt) end
      end
    elseif FORWARD[name] then
      love[name]=function(...)
        if handler then handler(...) end
        if original then return original(...) end
      end
    else
      love[name]=handler or function() end
    end
  end
end

function Room:uninstall()
  for name,entry in pairs(self.saved or {}) do love[name]=entry.value end
  self.saved=nil
end

function Room:close()
  if current~=self then return end
  current=nil
  self:uninstall()
  if self.scene then self.scene:release();self.scene,self.adapter=nil,nil end
  Camera.recentre();Camera.reset()
  for _,font in pairs(self.fonts) do if font.release then font:release() end end
  self.fonts={}
  local stack=self.game and self.game.stack
  if stack and stack:top()==self.state then stack:pop() end
end

Room.SCENES=SCENES
function Room.isOpen() return current~=nil end
function Room.currentRoom() return current end
function Room.closeCurrent() if current then current:close() end end

function Room.open(game)
  if current or not (game and game.stack and love and love.graphics) then return false end
  local room=Room.new(game)
  current=room
  -- Blocking, opaque state: the game underneath does not update or read input.
  room.state={isOpaque=true,stadium2TestRoom=true,update=function() end,draw=function() end,
    exit=function() if current==room then room.state=nil;room:close() end end}
  game.stack:push(room.state)
  room:install()
  Camera.recentre();Camera.reset()
  room:buildScene()
  room:play()
  return true
end

-- Row for the game's own OPTIONS menu (an action row, like STADIUM 2 ROM).
function Room.optionsRow(game)
  return {id="STADIUM2_IMPORTER:test_room",stadium2TestRoom=true,label="FX TEST ROOM",
    value=function() return "OPEN" end,
    activate=function() Room.open(game);return true end}
end

return Room
