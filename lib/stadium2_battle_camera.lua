-- The STADIUM camera option: Stadium 2's own battle camera, run from the Lua
-- port (stadium2_battle_camera_native.lua) at 30 Hz, and its eye / target /
-- FOV handed to the arena frame. The FREE option keeps the field camera.
--
-- Battle state it needs, in Stadium 2's own structs and units:
--   actors: position and facing from Stadium's layout (8411EFE4's home pose),
--     species, and the per-species camera record from the ROM (84113014 /
--     84112704: archive 0x49B780 + 0x22E0, 0x30 bytes per species);
--   the marker point (8411DD8C) from the model's attachment markers;
--   the battle record (HP per side).
-- Director so far (native evidence in docs/luna/research/battle-camera.md):
--   battle start: program 0, shot 0 on the player (states set 0 on entry);
--   a move (event 0, state family 2, 84114A04): the move's attack shot
--     (84114804) and program 0 (5 / 13 / 3 / 17 for Fly, Surf, Waterfall,
--     Rapid Spin) on the attacker;
--   the defender's hit (event 0x0A / 0x0B asleep / 0x0D frozen, queued by
--     84124604; family 4, 841170A0): the move's hit shot (84116BC0) and
--     program 1 on the defender. The host calls it at the impact; the ROM
--     enters that state when the defender's record is read.
--   a miss (841246AC: event 0x11 / 0x12 frozen / 0x13 asleep on the
--     defender; the attacker gets no move event): the same hit state, whose
--     0x11 shot is a random one of D_84183BDC and whose program 1 holds its
--     pose on 0x11. The host calls it when the miss is presented.
--   a status or residual event (family 9, 84118C08: poison, burn, Leech
--     Seed, trapping, stat changes, healing, love...): the shot by event
--     code and program 0 on that side, when the host signals its FX entry.
--   a recall (family 18, 8411ABAC: event 0x1E / 0x1F asleep / 0x20
--     frozen): a recall shot of D_84183C7C (0x11 when frozen) and program
--     27 on the outgoing Pokemon, when the host starts its recall.
--   the turn check (84127194; family 17, 84119CF0): fast asleep (4),
--     frozen solid (2), defrosted (0x2C), and the recharge / flinch
--     reactions (84124594); shot 0 and program 0 on that side. The engine
--     has no event for these, so the hosts match the exact line shown.
--   Dig (family 15, 84115E28): shot 0x0E and program 6; Substitute (family
--     11, Dispatch_079): the move's shot and program 0, then on the 31st
--     tick the doll's camera record, shot 0 and program 0. Transform (13,
--     8411B070) and Beat Up (22, Dispatch_156): the move's shot and program
--     0; their animation-timed later shots are not ported.
--   Substitute faded (family 21): shot 0 / program 0, then Stadium's swap
--     back from the doll and the same shot on the 31st tick; dragged out
--     (family 25): shot 0 / program 0 a tick later, the kind reset on the
--     66th tick. From the exact lines.
--   the confusion self-hit (family 16, Dispatch_114): a random shot of
--     D_84183BDC and program 0, on the side of the "is confused!" line
--     just before it (the engines print that line first, as Stadium does).
--   charge turns (families 6, 7, 8): Fly's rise (program 3), Dig's hole
--     (shot 0, then shot 0x10 / program 2), and the charge shots of Razor
--     Wind, Solar Beam, Skull Bash and Sky Attack; from the exact line.
--   woke up (family 19, 84119908): program 7's close-up from the species
--     offset row, or shot 0 when the side's flags have bit 2; confused
--     (family 20, Dispatch_142): shot 0x24 or 0, then the kind reset 30
--     ticks later. Both from the exact turn-check line.
--   weather (family 28, 841193E0: events 0x30-0x35 for battler 0):
--     program 29's wide arena shot; full paralysis (0x36, 8411957C): shot 0
--     and program 0 on that side. Both when the host signals their entries.
--   a turn begins (event 0x5A, 8411F94C, once both sides have chosen): a
--     random turn shot (D_84183C60) and program 10 on the player. Stadium
--     holds the turn's records until that orbit arrives (the event timer);
--     the host does not wait for it.
--   a faint (event 0x1C, family 5, 8411A544): a faint shot (D_84183C74)
--     and program 11 on the fainting actor, when its faint clip starts.
--   a send-out (family 12, 8411BB04 / 8411BCC8): the opening shot on the
--     actor, then the send-out's per-frame moves for 0x61 frames, then
--     program 26. Stadium waits for the ball's throw and the Pokemon's
--     appearance before counting frames; the host starts at its send-out.
-- A handler that is not ported yet is reported once and skipped.
local Native = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_camera_native")
local bit = require("bit")
local Layout = require("mods.STADIUM2_IMPORTER.lib.stadium_battle_layout")
local Endpoints = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_endpoints")

local StadiumCamera = {}
StadiumCamera.__index = StadiumCamera

-- The GeoCameras are the game's own (D_84190428 / D_841910E0): the intro's
-- view functions address them directly.
local C0, C1 = 0x85000000, 0x85000100
local GC0, GC1 = Native.VIEW0, Native.VIEW1
local ACTOR = { player = 0x85001000, enemy = 0x85002000 }
local SIDE_OF = { [0x85001000] = "player", [0x85002000] = "enemy" }
local RECORD = 0x85003000
StadiumCamera.TICK = 1 / 30
StadiumCamera.CAMERA_RECORDS = 0x49B780 + 0x22E0 -- ROM, 0x30 per species
-- 84113014: the species offset row +0x678 points at (D_84193DF8 + side *
-- 0x20), DMA'd from the archive's first table (0x49B780 + 0), 0x20 bytes per
-- species; program 7 (woke up) reads it. (The + 0x5730 rows go to
-- D_84193E98, +0x668; the + 0x22E0 rows to D_84193E38, +0x664.)
StadiumCamera.OFFSET_RECORDS = 0x49B780
local OFFSET_ROW = { player = 0x84193DF8, enemy = 0x84193E18 }
-- Each actor's motion record (+0x2D4, 0x1530 bytes; 84113014's copy of the
-- species' animation-dispatch record)
local MOTION = { player = 0x85010000, enemy = 0x85012000 }

-- The species' compressed motion records (the animation-dispatch archive),
-- kept so a record can be decoded when its species appears.
function StadiumCamera.motionArchive(rom)
  local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
  local Dispatch = require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
  local archive = type(rom) == "string" and Rom.archiveAt(rom, Dispatch.ARCHIVE_START)
  if not archive then return nil end
  local out = {}
  for species = 1, Dispatch.ARCHIVE_RECORDS do out[species] = Rom.recordBytes(rom, archive.records[species]) end
  return out
end
-- 251 species and the Substitute doll (0xFC, 84112B64)
StadiumCamera.ROWS = 0xFC
StadiumCamera.DOLL = 0xFC

local function f32be(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  local word = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
  return require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory").wordFloat(word)
end

-- opts: rom (normalised ROM bytes), fragment79, warn, seed
function StadiumCamera.new(opts)
  opts = opts or {}
  local self = setmetatable({ accumulator = 0, species = {}, warn = opts.warn,
    seed = (tonumber(opts.seed) or os.time()) % 4294967296 }, StadiumCamera)
  local introPaths = opts.introPaths
  if not introPaths and type(opts.rom) == "string" and type(opts.fragment79) == "string" then
    introPaths = Native.introPathBytes(opts.rom, opts.fragment79)
  end
  local speciesShots = opts.speciesShots or (type(opts.rom) == "string" and #opts.rom > 0x49B780 + 0xE0A0
    and opts.rom:sub(0x49B780 + 0xE0A0 + 1, 0x49B780 + 0xE0A0 + 252 * 0x10)) or nil
  local cam, err = Native.load(opts.rom, opts.fragment79, {
    introPaths = introPaths, speciesShots = speciesShots,
    warn = opts.warn,
    markerPosition = function(actor) return self:markerPosition(actor) end,
    -- D_8418C958 (program 25): the battle FX player's dynamic anchors, which
    -- its port of 84102750 fills (nil while MOVE EFFECTS is off)
    attachmentPoint = function(index)
      local fx = self.scene and self.scene.battleFx
      local player = fx and fx.player
      if not (player and type(player.dynamicAnchor) == "function") then return nil end
      local ok, point = pcall(player.dynamicAnchor, player, index)
      if ok and type(point) == "table" and tonumber(point[1]) and tonumber(point[2]) and tonumber(point[3]) then
        return { point[1], point[2], point[3] }
      end
      return nil
    end,
    random = function() return self:random() end,
  })
  if not cam then return nil, err end
  self.cam = cam
  -- keep only the camera records (251 species), not the whole ROM
  self.records = opts.records or opts.rom:sub(StadiumCamera.CAMERA_RECORDS + 1,
    StadiumCamera.CAMERA_RECORDS + StadiumCamera.ROWS * 0x30)
  self.offsets = opts.offsets or opts.rom:sub(StadiumCamera.OFFSET_RECORDS + 1,
    StadiumCamera.OFFSET_RECORDS + StadiumCamera.ROWS * 0x20)
  self.timed = {}
  self.doll = {}
  self.runs = {}
  self.transformed = {}
  self.motionBlobs = opts.motionBlobs or StadiumCamera.motionArchive(opts.rom)
  self.speciesShots = opts.speciesShots or (type(opts.rom) == "string" and #opts.rom > 0x49B780 + 0xE0A0
    and opts.rom:sub(0x49B780 + 0xE0A0 + 1, 0x49B780 + 0xE0A0 + 252 * 0x10)) or nil
  self.motionCache = {}
  local m = cam.mem
  m:setU32(Native.CONTROLLER0, C0); m:setU32(Native.CONTROLLER1, C1)
  m:setU32(C0, GC0); m:setU32(C1, GC1)
  m:setU32(Native.PLAYER, ACTOR.player); m:setU32(Native.ENEMY, ACTOR.enemy)
  m:setU32(Native.RECORD, RECORD)
  -- 8410B2DC: near 20, far 6400, FOV 45
  for _, gc in ipairs({ GC0, GC1 }) do
    m:setF32(gc + 0x34, 20); m:setF32(gc + 0x38, 6400); m:setF32(gc + 0x2C, 45)
  end
  cam:clearProgram(); cam:clearProgram1()
  -- the full-screen first view, drawn; the second view is not
  m:setU16(C0 + 0x9E, 0x140); m:setU16(C0 + 0xA0, 0xF0)
  m:setU8(GC0 + 1, bit.bor(m:u8(GC0 + 1), Native.VIEW_DRAWN))
  m:setU8(GC1 + 1, bit.band(m:u8(GC1 + 1), 0xFF - Native.VIEW_DRAWN))
  return self
end

-- The per-species camera record into the actor (84112704).
function StadiumCamera:loadRecord(address, species)
  local m = self.cam.mem
  local base = (species - 1) * 0x30
  local function at(o) return f32be(self.records, base + o) end
  m:setF32(address + 0x644, at(0x20)); m:setF32(address + 0x640, at(0x1C))
  m:setF32(address + 0x654, at(0x0C)); m:setF32(address + 0x64C, at(0x04))
  m:setF32(address + 0x650, at(0x08)); m:setF32(address + 0x634, at(0x10))
  m:setF32(address + 0x638, at(0x14)); m:setF32(address + 0x63C, at(0x18))
  m:setF32(address + 0x648, at(0x14))
end

-- 84112704 and 84113014's camera parts: the species' camera record and
-- offset row (+0x678).
function StadiumCamera:motionRecord(species)
  if self.motionCache[species] then return self.motionCache[species] end
  local blob = self.motionBlobs and self.motionBlobs[species]
  if not blob then return nil end
  local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
  local payload = Rom.decompress(blob)
  if type(payload) ~= "string" or #payload ~= 0x1530 then return nil end
  self.motionCache[species] = payload
  return payload
end

function StadiumCamera:loadSpecies(address, side, species)
  local m = self.cam.mem
  self:loadRecord(address, species)
  -- 84113014 / the battler's motion record at +0x2D4 (the doll, 0xFC, has
  -- no record in the archive; the Pokemon's stays)
  local record = self:motionRecord(species)
  if record then
    for i = 1, #record do m:setU8(MOTION[side] + i - 1, record:byte(i)) end
    m:setU32(address + 0x2D4, MOTION[side])
  end
  for i = 0, 0x1F do m:setU8(OFFSET_ROW[side] + i, self.offsets:byte((species - 1) * 0x20 + i + 1)) end
  m:setU32(address + 0x678, OFFSET_ROW[side])
end

-- 84112B64's camera part (Substitute, 8411B3B8 substate 2): the actor
-- becomes the doll (+0x658 = 0xFC) and takes its camera record and offset
-- row, unless the side's flags have bit 2 and it is Diglett or Dugtrio, or
-- it is the doll already. +0x7EA = 0. The doll stays until 84112C98 swaps
-- it back (Substitute faded) or the side sends out another Pokemon.
function StadiumCamera:substituteDoll(address, side)
  local m = self.cam.mem
  local species = m:s16(address + 0x658)
  local flags = m:u16(RECORD + (side == "player" and 0 or 1) * 16 + 0x12)
  if bit.band(flags, 4) ~= 0 and (species == 0x32 or species == 0x33) then return end
  if species == StadiumCamera.DOLL then return end
  m:setU16(address + 0x658, StadiumCamera.DOLL)
  self:loadSpecies(address, side, StadiumCamera.DOLL)
  self.doll[side] = true
  m:setU16(address + 0x7EA, 0)
end

-- 84112C98's species part (the swap back from the doll): when +0x658 is
-- not the actor's own species (+0x65C, here the synced species), restore it
-- and reload its camera record and offset row.
function StadiumCamera:substituteRestore(address, side)
  local m = self.cam.mem
  local species = self.species[side]
  self.doll[side] = nil
  if not species or m:s16(address + 0x658) == species then return end
  m:setU16(address + 0x658, species)
  self:loadSpecies(address, side, species)
end

-- The battle scene into Stadium's actor structs and battle record.
function StadiumCamera:sync(scene)
  local m = self.cam.mem
  self.scene = scene
  for side, address in pairs(ACTOR) do
    local actor = scene and scene.actors and scene.actors[side]
    local species = actor and tonumber(actor.dex)
    -- a transformed actor keeps its own species' data (8411AE08 changes only
    -- the display model, +0x65C); the host shows the copy by loading it
    if self.transformed[side] and self.species[side] then species = self.species[side] end
    if species and species >= 1 and species <= 251 then
      if self.species[side] ~= species then
        self.species[side] = species
        self.doll[side] = nil
        m:setU16(address + 0x1A, species); m:setU16(address + 0x658, species)
        self:loadSpecies(address, side, species)
        m:setF32(address + 0x34, 1)
      elseif not self.doll[side] and m:s16(address + 0x658) ~= species then
        m:setU16(address + 0x658, species)
        self:loadSpecies(address, side, species)
      end
      local slot, yaw = Layout.slot(side, species)
      m:setF32(address + 0x24, slot[1]); m:setF32(address + 0x2C, slot[3])
      m:setF32(address + 0x28, m:f32(address + 0x650)) -- 8411EFE4
      m:setU16(address + 0x20, math.floor(yaw * 0x10000 / (2 * math.pi) + 0.5) % 0x10000)
      local mon = actor.mon
      local hp = mon and tonumber(mon.hp) or 1
      m:setU16(RECORD + (side == "player" and 0 or 1) * 16 + 0xE, math.max(0, math.floor(hp)) % 0x10000)
    end
  end
end

-- 8411DD8C: the actor's height marker point, in Stadium units.
function StadiumCamera:markerPosition(address)
  local side = SIDE_OF[address]
  local m = self.cam.mem
  local fallback = { m:f32(address + 0x24), m:f32(address + 0x638), m:f32(address + 0x2C) }
  local scene = self.scene
  local actor = scene and scene.actors and scene.actors[side]
  local renderer = actor and actor.renderer
  local ok, matrix = pcall(function() return scene:modelMatrix(side, actor) end)
  if not (ok and type(matrix) == "table" and renderer and renderer.attachmentPositions) then
    self:report("marker", "battle camera: no model markers for the " .. tostring(side)
      .. "; its anchor point stands in for 8411DD8C")
    return fallback
  end
  local Adapter = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
  local units = Adapter.worldUnits({ scene = { host = scene } }, side)
  local toStadium = type(scene.worldToStadium) == "function" and function(w) return scene:worldToStadium(w) end
  local markers = {}
  for label, p in pairs(renderer.attachmentPositions) do
    local world = {}
    for k = 1, 3 do
      local j = (k - 1) * 4
      world[k] = matrix[j + 1] * p[1] + matrix[j + 2] * p[2] + matrix[j + 3] * p[3] + matrix[j + 4]
    end
    -- world -> Stadium units through the scene's Stadium space (the arena,
    -- or a custom scene's fitted layout)
    markers[label] = toStadium and toStadium(world) or { world[1] / units, world[2] / units, world[3] / units }
  end
  local point = Endpoints.heightPoint({ species = self.species[side], markers = markers,
    specialHeightPoint = actor.nativeFxHeightPoint })
  if not point then
    self:report("marker-label", "battle camera: the " .. tostring(side)
      .. " model has no height marker; its anchor point stands in for 8411DD8C")
    return fallback
  end
  return point
end

function StadiumCamera:report(key, message)
  self.reported = self.reported or {}
  if self.reported[key] then return end
  self.reported[key] = true
  if self.warn then pcall(self.warn, message) end
end

-- The game's LCG (8003570C) on a private seed: presentation only, never the
-- battle's RNG.
function StadiumCamera:random()
  self.seed = Native.nextRandom(self.seed)
  return self.seed
end

-- Battle start: program 0 with shot 0 on the player.
-- Battle start: the arena intro (event 0x65, 8413D37C; family 26 on the
-- player's actor). 8411D65C picks the path: 8003570C % 5 in the plain game
-- modes (path 5, families 33 / 34, belongs to modes the host does not have).
-- 8410890C through the scene's battle FX (the send-out throws: 0x112 at
-- the arena intro, 0x124 in the opening's wipe).
local function signalEffect(scene, entry, side)
  local fx = scene and scene.battleFx
  if fx and type(fx.signalEffect) == "function" then pcall(fx.signalEffect, fx, entry, side) end
end

local function wildBattle(scene)
  local okW, wild = pcall(function() return scene and scene.stadiumWildBattle and scene:stadiumWildBattle() end)
  return okW and wild == true
end

function StadiumCamera:start(scene)
  self:sync(scene)
  self.started = true
  self.openingPhase = true
  self.wildBattle = wildBattle(scene)
  if self.wildBattle then return self:wildEncounter(scene) end
  self:arenaIntro(scene, self:random() % 5)
end

-- USER-REQUESTED EXTENSION (not in Stadium 2, which has no wild battles):
-- the wild Pokemon was not thrown out, so there is no split-screen intro.
-- The camera holds the wild Pokemon's own Stadium close-up (its species shot
-- row 0x27, 84113658, with program 12) for WILD_CLOSEUP ticks, then Stadium's
-- slow arena orbit (program 4) until the player's send-out, which runs the
-- native opening (family 24).
StadiumCamera.WILD_CLOSEUP = 60
function StadiumCamera:wildEncounter(scene)
  self:sync(scene)
  self:newFamily(ACTOR.enemy)
  local m = self.cam.mem
  self.cam:loadSpeciesShot(ACTOR.enemy)
  m:setU16(C0 + 0x98, 0x27)
  self.cam:setProgram(ACTOR.enemy, 0xC)
  self.wildIntro = { frame = 0 }
end

-- 84113590's load, 8411FF1C, 8411C8A0's camera part; Dispatch_184 zeroes
-- the player's frame counter a tick later, so 8411C9DC's first frame is 1.
function StadiumCamera:arenaIntro(scene, path)
  self:sync(scene)
  self:newFamily(ACTOR.player)
  local m = self.cam.mem
  m:setU16(RECORD + 4, 0x65)
  self.cam:loadIntroPath(path)
  self.cam:arenaIntroSetup()
  self.intro = { substate = 1, frame = 0, path = path }
end

-- Starts the host's held entrance animation for a side (Scene:stadiumEntrance).
local function releaseEntrance(scene, side)
  if scene and type(scene.stadiumReleaseEntrance) == "function" then pcall(scene.stadiumReleaseEntrance, scene, side) end
end

-- The host can move on before the intro or the opening ends (Stadium's
-- engine waits for them; the host does not). Then the running sequence stops
-- and the split is closed at once with 8410B104. This is the port's fallback
-- for host timing, not a ROM path.
function StadiumCamera:cutIntro()
  if not (self.intro or self.opening) then return end
  self.intro, self.opening = nil, nil
  self.pendingOpening, self.openingPhase = nil, nil
  self.cam:endSplit()
  -- no held entrance is lost when the host moves on
  releaseEntrance(self.scene, "player")
  releaseEntrance(self.scene, "enemy")
end

-- The battle's opening starts the entrance animations itself (8411C310
-- plays 0xFC on the player as it sets up; 8411C418 plays it on the foe at
-- frame 0x28 of substate 4), while the host starts them at its send-outs,
-- which can come during the arena intro. Until the opening reaches that
-- point, the host's entrance for that side is held and released here.
function StadiumCamera:holdEntrance(side)
  if side == "player" then
    return (self.openingPhase or self.pendingOpening) and true or false
  end
  if side == "enemy" then
    if self.wildBattle then return false end
    return (self.openingPhase or self.intro ~= nil or self.pendingOpening
      or (self.opening ~= nil and not self.foeEntranceReleased)) and true or false
  end
  return false
end

-- The opening send-out (event 0x22, family 24 on the player's actor):
-- Dispatch_169 zeroes the player's frame counter, 8411C310 sets up, then
-- 8411C418 runs each tick. 8003EC34 (the model animation has ended) is the
-- host actor's entrance clip having ended.
function StadiumCamera:openingSendOut(scene)
  self:sync(scene)
  self:newFamily(ACTOR.player)
  local m = self.cam.mem
  m:setU16(RECORD + 4, 0x22)
  m:setU16(ACTOR.player + 0x7E8, 0)
  self.cam:openingSetup()
  self.opening = { substate = 1 }
  self.foeEntranceReleased = nil
  -- 8411C310: 84112158(player, 0xFC), the player's entrance animation
  releaseEntrance(scene, "player")
end

-- 8003EC34 (ModelAnim_IsFinished): the host actor is no longer playing a
-- Stadium clip other than its idle loop (Actor:update returns it to "idle"
-- when the clip ends).
local function clipEnded(scene, side)
  local actor = scene and scene.actors and scene.actors[side]
  if not actor then return true end
  return actor.context == nil or actor.context == "idle"
end
StadiumCamera.clipEnded = clipEnded

-- Fly's height check (841156D0: 200 above home): the host's Fly vanish has
-- finished its departure (restCondition's `flying`).
local function flownUp(scene, side)
  local okC, c = pcall(function() return scene and scene.restCondition and scene:restCondition(side) end)
  return okC and type(c) == "table" and c.flying == true
end

local function entranceEnded(scene, side)
  local actor = scene and scene.actors and scene.actors[side]
  if not actor then return true end
  return actor.context ~= "entrance"
end

-- A move starts: event 0 on the attacker, 84114A04's camera part.
function StadiumCamera:attack(scene, side, moveId)
  local address = ACTOR[side]
  moveId = tonumber(moveId)
  if not address then return end
  if not moveId or moveId < 1 or moveId > 251 then
    self:report("attack-move", "battle camera: a move without a Stadium move ID; its attack shot is skipped")
    return
  end
  self:sync(scene)
  self:newFamily(address)
  local m = self.cam.mem
  m:setU16(RECORD + 4, 0)
  m:setU8(address + 0x618, moveId)
  if moveId == 0x5B then
    -- Dig: family 15 (Dispatch_106 sets +0x7F6 = 5, then 84115E28)
    m:setU8(address + 0x7F6, 5)
    return self.cam:digState(address)
  elseif moveId == 0xA4 then
    -- Substitute: family 11 (Dispatch_078, Dispatch_079 with +0x7F6 = 1,
    -- then 8411B3B8's substate 2 on the 31st tick: the doll swap)
    self.cam:substituteState(address)
    m:setU8(address + 0x7F6, 1)
    local side = SIDE_OF[address]
    self.timed[address] = { frame = 0, at = 0x1F, run = function(actor)
      self:substituteDoll(actor, side)
      self.cam:substituteDollState(actor)
    end }
    return
  elseif moveId == 0x90 then
    -- Transform: family 13 (Dispatch_092, then 8411B070), then 8411B1F4's
    -- substates; 800427B8 (the new model is loaded) is the host actor showing
    -- another species than its own
    m:setU8(address + 0x7F6, 1)
    self.cam:transformState(address)
    local side = SIDE_OF[address]
    self.transformed[side] = true
    local run = { substate = 1 }
    run.step = function(sc)
      local actor = sc and sc.actors and sc.actors[side]
      local shown = actor and tonumber(actor.dex)
      local ready = shown ~= nil and shown ~= self.species[side]
      run.substate = self.cam:transformFrame(address, run.substate, ready)
      return run.substate == 5
    end
    self.runs[address] = run
    return
  elseif moveId == 0xFB then
    -- Beat Up: family 22 (84116460, then Dispatch_156), then 84116808's
    -- substates; 8003EC34 is the host actor's clip having ended
    m:setU8(address + 0x7F6, 1)
    m:setU8(RECORD + 8, moveId)
    self.cam:beatUpState(address)
    local run = { substate = 1 }
    run.step = function(sc, side)
      run.substate = self.cam:beatUpFrame(address, run.substate, clipEnded(sc, side))
      return run.substate == 4
    end
    self.runs[address] = run
    return
  end
  self.cam:attackState(address)
  -- 841154F8 -> 84114BF4 each tick until the attack ends (its row length
  -- +0x61A, or the attacker's clip when that is 0). The defender's hit or
  -- dodge record only plays after that (84135778 waits for the attack's
  -- timer), so the camera stays on the attacker until then. Rest (0x9C)
  -- runs 841153DC instead and has no hit.
  if moveId ~= 0x9C then
    self.attacking = { actor = address }
    self.runs[address] = { step = function(sc, s)
      local done = self.cam:attackFrame(address, clipEnded(sc, s))
      if done then
        self.attacking = nil
        local held = self.heldHit
        self.heldHit = nil
        if held then self[held.kind](self, sc, held.side, held.moveId, held.condition, true) end
      end
      return done
    end }
  end
end

-- A hit or dodge reported while the other side's attack state still runs
-- waits for it (the record gate); `deferred` marks one released that way.
function StadiumCamera:holdHit(kind, address, side, moveId, condition)
  if self.attacking and self.attacking.actor ~= address then
    self.heldHit = { kind = kind, side = side, moveId = moveId, condition = condition }
    return true
  end
  return false
end

-- The defender is hit: 84124604's event code (0x0B asleep, 0x0D frozen,
-- else 0x0A), then 841170A0's camera part on the defender.
-- Family 9's events by the FX entry the host signals for them (the codes
-- that queue each entry: stadium2_battle_fx_sequence.lua and
-- docs/luna/research/battle-event-effects.md).
StadiumCamera.ENTRY_EVENT = {
  [0x101] = 0x3C, [0x102] = 0x3E, [0x103] = 0x3F, [0x10A] = 0x40, [0x109] = 0x43,
  [0x10B] = 0x46, [0x108] = 0x06, [0x10D] = 0x4A, [0xFC] = 0x41, [0xFD] = 0x42,
  [0x117] = 0x51, [0x115] = 0x52, [0x116] = 0x53, [0x114] = 0x54,
  [0x125] = 0x48, -- the sandstorm hurts a battler
}
-- Family 28's events by entry (841324EC HandleWeather on battler 0, and
-- 84127194's full paralysis): rain / sun / sandstorm continuing 0x32 /
-- 0x31 / 0x30, ending 0x35 / 0x34 / 0x33; fully paralysed 0x36.
StadiumCamera.WEATHER_EVENT = { [0x107] = 0x32, [0x106] = 0x31, [0x113] = 0x30,
  [0x11F] = 0x35, [0x121] = 0x34, [0x120] = 0x33 }
StadiumCamera.PARALYSIS_ENTRY = 0x10C
-- 84132778: a trapping tick's code by the trapping move (Fire Spin 0x4C,
-- Clamp 0x58, Whirlpool 0x50, any other 0x45).
StadiumCamera.TRAP_EVENT = { [83] = 0x4C, [128] = 0x58, [250] = 0x50 }

-- A status or residual event on `side`: 84118C08's camera part (family 9).
-- `entry` is the FX entry the host signals for it; other entries are not
-- family 9 and are ignored.
function StadiumCamera:statusEvent(scene, side, entry, trapMove)
  entry = tonumber(entry)
  local weather = StadiumCamera.WEATHER_EVENT[entry]
  if weather then return self:weather(scene, weather) end
  local address = ACTOR[side]
  if not address then return end
  if entry == StadiumCamera.PARALYSIS_ENTRY then
    self:sync(scene)
    self:newFamily(address)
    self.cam.mem:setU16(RECORD + 4, 0x36)
    -- 8411938C sets +0x7F6 = 1, 841193E0 sets 2 on frame 2 (as family 9)
    self.cam.mem:setU8(address + 0x7F6, 2)
    return self.cam:paralysisState(address)
  end
  local code = StadiumCamera.ENTRY_EVENT[entry]
  if not code and trapMove then code = StadiumCamera.TRAP_EVENT[tonumber(trapMove)] or 0x45 end
  if not code then return end
  self:sync(scene)
  self:newFamily(address)
  local m = self.cam.mem
  m:setU16(RECORD + 4, code)
  -- 84118990 sets +0x7F6 = 1; 841189EC sets 2 on frame 2 as it signals the
  -- entry, the frame 84118C08 runs. The host calls this at that signal.
  m:setU8(address + 0x7F6, 2)
  self.cam:endSplit() -- Dispatch_064 (family 9's first state): 8410B104
  self.cam:residualState(address)
end

-- Weather (event 0x30-0x35, queued for battler 0): 841193E0's camera part,
-- program 29's arena shot, on the player's actor.
function StadiumCamera:weather(scene, code)
  self:sync(scene)
  self:newFamily(ACTOR.player)
  self.cam.mem:setU16(RECORD + 4, code)
  self.cam:weatherState(ACTOR.player)
end

-- The turn check on `side` (84127194): `code` is the Stadium event queued
-- with its text, or "react" for 84124594's reaction (4 asleep, 2 frozen,
-- else 3). 0x36 (fully paralysed) and 6 (in love) belong to families 28
-- and 9; the rest to family 17 (84119CF0).
function StadiumCamera:turnCheck(scene, side, code, condition)
  local address = ACTOR[side]
  if not address then return end
  condition = condition or {}
  if code == "react" then code = condition.asleep and 4 or condition.frozen and 2 or 3 end
  if code == 0x36 then return self:statusEvent(scene, side, StadiumCamera.PARALYSIS_ENTRY) end
  if code == 6 then return self:statusEvent(scene, side, 0x108) end
  if code == 0x1D then return self:wokeUp(scene, side) end
  if code == 1 then return self:selfHit(scene, side) end
  if code == 0x27 then return self:substituteFaded(scene, side) end
  if code >= 0x2D and code <= 0x2F then return self:dragOut(scene, side, code) end
  if code >= 0x16 and code <= 0x1B then return self:chargeTurn(scene, side, code) end
  if code == 0x26 then return self:confused(scene, side) end
  self:sync(scene)
  self:newFamily(address)
  self.cam.mem:setU16(RECORD + 4, code)
  self.cam:endSplit() -- Dispatch_120 (family 17's first state): 8410B104
  self.cam:turnCheckState(address)
end

-- A charge turn (8412C47C queues the code after its text; no move event
-- that turn): 0x16-0x19 family 8 (84116138), 0x1A Fly family 6 (841155E8),
-- 0x1B Dig family 7 (84115A64, then 84115B34's shot 0x10 / program 2 on
-- the 26th tick: frame 0x19 moves it to substate 1). Fly's second shot
-- (841157D8: shot 8, program 15) waits until the model is 200 above its home
-- height (841156D0); the host's Fly departure having finished stands in for
-- that height (flownUp).
function StadiumCamera:chargeTurn(scene, side, code)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  local m = self.cam.mem
  m:setU16(RECORD + 4, code)
  if code == 0x1A then
    self.cam:flyUpState(address)
    -- Dispatch_045: the rise (841156D0), then shot 8 / program 15 (841157D8)
    local run = { substate = 0 }
    run.step = function(sc, side)
      run.substate = self.cam:flyRiseFrame(address, run.substate, flownUp(sc, side))
      return run.substate == 1 and m:s16(address + 0x7E8) >= 0x1E
    end
    self.runs[address] = run
    return
  end
  if code == 0x1B then
    -- 84115A64, then 84115B34: frame 0x19 -> shot 0x10 / program 2 on the
    -- next tick -> sunk (the host's Dig departure has finished) or, for
    -- Diglett / Dugtrio, the clip's end -> the kind reset at frame 0x1E
    self.cam:digHoleState(address)
    local run = { substate = 0 }
    run.step = function(sc, side)
      if run.substate == 0 then
        if m:s16(address + 0x7E8) == 0x19 then run.substate = 1 end
      elseif run.substate == 1 then
        self.cam:digHoleShot(address); run.substate = 2
      else
        local okC, c = pcall(function() return sc and sc.restCondition and sc:restCondition(side) end)
        local sunk = okC and type(c) == "table" and c.underground == true
        local before = m:u8(address + 0x61F)
        run.substate = self.cam:digHoleFrame(address, run.substate, sunk, clipEnded(sc, side))
        if run.substate == 3 and m:s16(address + 0x7E8) == 0 and before ~= 0xFF and m:u8(address + 0x61F) == 0xFF then return true end
      end
      return false
    end
    self.runs[address] = run
    return
  end
  self.cam:chargeState(address)
  -- Dispatch_059 / 84116248: the follow-up on the row's frames (the US rows
  -- never wait on the animation: +0x61A is never 0 for them)
  local run = { substate = 0 }
  run.step = function(sc, side)
    run.substate = self.cam:chargeFollowFrame(address, run.substate, clipEnded(sc, side))
    return run.substate ~= 0
  end
  self.runs[address] = run
end

-- Substitute faded (event 0x27, family 21): Dispatch_148 makes sure the
-- actor is the doll (84112B64), Dispatch_149 takes shot 0 / program 0, and
-- 8411B5A8 swaps back (84112C98) and takes them again on the 31st tick
-- (its frame 0x1E, counted from Dispatch_148's zero).
function StadiumCamera:substituteFaded(scene, side)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  self.cam.mem:setU16(RECORD + 4, 0x27)
  self:substituteDoll(address, side)
  self.cam:substituteFadedState(address)
  self.timed[address] = { frame = 0, at = 0x1F, run = function(actor)
    self:substituteRestore(actor, side)
    self.cam:substituteFadedShot(actor)
  end }
end

-- Dragged out (events 0x2D-0x2F, family 25; 0x2F follows "was dragged
-- out!"): once the new model is ready (Dispatch_177, assumed at once), the
-- next tick takes shot 0 / program 0 (8411B898 substate 1); substate 2 ends
-- at its frame 5 and substate 3 resets the kind at its frame 0x3C, the 66th
-- tick (0x2F also clears +0x7F4 bit 0, 0x2E bit 1).
function StadiumCamera:dragOut(scene, side, code)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  local m = self.cam.mem
  m:setU16(RECORD + 4, code)
  self.timed[address] = { frame = 0, at = 1, run = function(actor)
    self.cam:dragOutShot(actor)
    self.timed[actor] = { frame = 1, at = 66, run = function(a)
      if code == 0x2F then m:setU16(a + 0x7F4, bit.band(m:u16(a + 0x7F4), 0xFFFE)) end
      if code == 0x2E then m:setU16(a + 0x7F4, bit.band(m:u16(a + 0x7F4), 0xFFFD)) end
      self.cam:kindReset(a)
    end }
  end }
end

-- The battle's end (84133C10 -> 8413D2E4): 0x67 on the winner (battler 0
-- for a draw) while either active Pokemon has HP, else 0x69 (8411F90C, the
-- idle state's arena orbit). `result` is the engine's battle.ended result:
-- win / lose / draw; the others (run, caught, fled) have no Stadium event.
function StadiumCamera:battleEnd(scene, result)
  local winner = ({ win = "player", lose = "enemy", draw = "player" })[result]
  if not winner then return end
  self:sync(scene)
  local m = self.cam.mem
  local standing = m:u16(RECORD + 0xE) ~= 0 or m:u16(RECORD + 0x1E) ~= 0
  local address = ACTOR[winner]
  self:newFamily(address)
  self.cam:setTimer(0x64)
  if standing then
    m:setU16(RECORD + 4, 0x67)
    self.cam:victoryState(address)
    m:setU16(address + 0x7E8, 0)
    self.victory = { actor = address, substate = 0 }
  else
    m:setU16(RECORD + 4, 0x69)
    self.cam:endSplit()
    self.cam:idleState(address)
  end
end

-- The confusion self-hit (event 1, family 16): Dispatch_114's camera part.
function StadiumCamera:selfHit(scene, side)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  self.cam.mem:setU16(RECORD + 4, 1)
  self.cam.mem:setU8(address + 0x618, 1) -- Dispatch_113
  self.cam:selfHitState(address)
  -- 84116AC4: the end on the row's frame (or the host clip's end)
  local run = { substate = 0 }
  run.step = function(sc, s)
    run.substate = self.cam:selfHitFrame(address, run.substate, clipEnded(sc, s))
    return run.substate == 1
  end
  self.runs[address] = run
end

-- Woke up (event 0x1D, family 19): 84119908's camera part.
function StadiumCamera:wokeUp(scene, side)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  self.cam.mem:setU16(RECORD + 4, 0x1D)
  self.cam:wakeState(address)
  -- 84119AB4, the tail: the wake animation's end is the host's clip having
  -- ended (the actor back to idle); it ends the timer and resets the kind
  local substate = self.cam.mem:u8(address + 0x7F6)
  self.runs[address] = { step = function(sc, s)
    substate = self.cam:wakeFrame(address, substate, clipEnded(sc, s))
    return substate == 3 or substate == 5
  end }
end

-- Confused (event 0x26, family 20): Dispatch_142's camera part, taken as
-- soon as 84113430 lets it run (its busy flag D_84193DDC & 0xC0 is assumed
-- clear); Dispatch_143 then resets the kind (841206D0) when the frame
-- counter Dispatch_142 zeroed reaches 0x1E, 30 ticks later.
function StadiumCamera:confused(scene, side)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  self.cam.mem:setU16(RECORD + 4, 0x26)
  self.cam:confusedState(address)
  self.timed[address] = { frame = 0, at = 0x1E, run = function(actor) self.cam:kindReset(actor) end }
end

-- A Pokemon is recalled: 84124C10's event (0x1F asleep, 0x20 frozen, else
-- 0x1E), then 8411ABAC's camera part on it.
function StadiumCamera:recall(scene, side, condition)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  condition = condition or {}
  self.cam.mem:setU16(RECORD + 4, condition.asleep and 0x1F or condition.frozen and 0x20 or 0x1E)
  self.cam:recallState(address)
end

-- The defender dodges (the move missed): 841246AC's event code (0x13
-- asleep, 0x12 frozen, else 0x11), then 841170A0's camera part on it.
function StadiumCamera:dodge(scene, side, moveId, condition, deferred)
  local address = ACTOR[side]
  moveId = tonumber(moveId)
  if not address or not moveId or moveId < 1 or moveId > 251 then return end
  if not deferred and self:holdHit("dodge", address, side, moveId, condition) then return end
  self:sync(scene)
  local m = self.cam.mem
  condition = condition or {}
  self:newFamily(address)
  m:setU16(RECORD + 4, condition.asleep and 0x13 or condition.frozen and 0x12 or 0x11)
  m:setU8(address + 0x618, moveId)
  -- a dodge's state starts with the host's miss (its length is 0x3C); a miss
  -- keeps result 1 (841246AC, 84128298 / 84130E04)
  self:startHit(scene, side, address, moveId, false, 1)
end

-- 841170A0 then 841187E4 each tick. The host reports a hit at its impact,
-- which is the defender's frame +0x619 (84117CAC plays the hit there), so
-- the frame counter starts there (one frame early, see below); a dodge
-- starts at the state's frame 0.
-- Record +9 is the move's result byte from the battle FX adapter (the same
-- value its effects use); without it the jolt is skipped (reported once).
-- The hit animation's length is the defender's hit clip (context 254, as
-- 84116EB4's 84112158(0xFE) selects), and the HP bar is the host's.
-- The hosts present one impact per move, so the record's hit index and
-- count (+0xB / +0xA) are equal.
function StadiumCamera:startHit(scene, side, address, moveId, atImpact, result)
  local m = self.cam.mem
  if result == nil then
    result = scene and type(scene.stadiumHitResult) == "function" and scene:stadiumHitResult(side, moveId)
  end
  m:setU8(RECORD + 9, tonumber(result) and result % 0x100 or 0)
  -- record +8 the move (80062D20's argument); +0xB / +0xA the hit and the
  -- count: a hit the host says is followed by another of the same move
  -- counts as not the last
  m:setU8(RECORD + 8, moveId % 0x100)
  local more = scene and type(scene.stadiumMoreHits) == "function" and scene:stadiumMoreHits(side)
  m:setU8(RECORD + 0xA, more and 2 or 1); m:setU8(RECORD + 0xB, 1)
  local frames = scene and type(scene.stadiumClipFrames) == "function" and scene:stadiumClipFrames(side, "hit")
  if not self.cam:hitStart(address, tonumber(frames)) then
    self:report("hit length", "battle camera: the defender's hit clip length is unknown; the hit state's end (841170A0) is not scheduled")
    return
  end
  -- one frame before the hit frame, so that program 1's setup (84120BB4
  -- ends any jolt) runs on the next tick before the jolt, as in the ROM
  if atImpact then m:setU16(address + 0x7E8, (m:s8(address + 0x619) - 1) % 0x10000) end
  local known = tonumber(result) ~= nil
  if not known then self:report("hit result", "battle camera: the move's result byte is unknown; the hit jolt (84117880) is skipped") end
  self.runs[address] = { step = function(sc, s)
    local settled = sc and type(sc.stadiumHpSettled) == "function" and sc:stadiumHpSettled(s)
    return self.cam:hitFollowFrame(address, settled == true, known)
  end }
end

function StadiumCamera:hit(scene, side, moveId, condition, deferred)
  local address = ACTOR[side]
  moveId = tonumber(moveId)
  if not address or not moveId or moveId < 1 or moveId > 251 then return end
  if not deferred and self:holdHit("hit", address, side, moveId, condition) then return end
  self:sync(scene)
  local m = self.cam.mem
  condition = condition or {}
  self:newFamily(address)
  m:setU16(RECORD + 4, condition.asleep and 0x0B or condition.frozen and 0x0D or 0x0A)
  m:setU8(address + 0x618, moveId)
  -- a hit held for the attack starts with its state (frame 0), as the
  -- record does in Stadium; otherwise it is lined up with the host's impact
  self:startHit(scene, side, address, moveId, not deferred)
end

-- A turn begins: 8411F94C's camera part (event 0x5A, side 0).
function StadiumCamera:turnStart(scene)
  self:sync(scene)
  self:newFamily(nil) -- 8411F94C puts both actors in family 0
  self.cam.mem:setU16(RECORD + 4, 0x5A)
  self.cam:setTimer(0x64) -- 8411F94C: 8411FEE8(0x64)
  self.cam:turnStart(ACTOR.player)
  -- 841347A0 runs the turn body (841343FC) right after queuing 0x5A, which
  -- queues 0x5B on the first mover; the record plays once 0x5A's timer is
  -- 0 (84135778 reads the current record D_84199D80's +2 and +6).
  self.firstMoverPending = true
  -- The idle records during command selection (8411F90C's 8410B104) close
  -- a split before this point in Stadium; the host can reach its turn start
  -- first (the opening still running), so the split is closed here too. This
  -- is a host-timing fallback, not a ROM path.
  self.cam:endSplit()
end

-- Event 0x5B on the side acting first (8411FF1C -> 8411F9D8): both actors
-- family 27, the side's actor program 18 (the Pokemon about to act).
function StadiumCamera:firstMover(scene, side)
  self:sync(scene)
  self:newFamily(nil)
  self.cam.mem:setU16(RECORD + 4, 0x5B)
  self.cam:firstMoverState(ACTOR[side])
end

-- 8413543C's idle cycle (fork C): the step (D_8419A006) picks the battler and
-- code; steps 0 / 1 are skipped for a battler asleep or frozen (status &
-- 0x27); after step 11 it goes back to step 2. D_8419A007 (0x63 instead of
-- 0x5F) is set by 8413C820, not identified; it stays 0. The step is 0 at the
-- battle's start (8413DE28) and after send-out records (84135808).
StadiumCamera.IDLE_STEPS = {
  [0] = { "player", 0x62 }, { "enemy", 0x62 }, { "player", 0x5C }, { "player", 0x5D },
  { "player", 0x60 }, { "player", 0x61 }, { "enemy", 0x60 }, { "enemy", 0x61 },
  { "player", 0x5E }, { "player", 0x64 }, { "player", 0x5F }, { "enemy", 0x5F },
}
StadiumCamera.FAMILY1_CAP = 0x78 -- Dispatch_009 ends the timer at frame 0x78 (or at the model animation's end)

function StadiumCamera:nextIdle(scene)
  local step = self.idleStep or 0
  local function resting(side)
    local okC, c = pcall(function() return scene and scene.restCondition and scene:restCondition(side) end)
    return okC and type(c) == "table" and (c.asleep or c.frozen)
  end
  if step == 0 and resting("player") then step = 1 end
  if step == 1 and resting("enemy") then step = 2 end
  local pick = StadiumCamera.IDLE_STEPS[step]
  step = step + 1
  if step >= 12 then step = 2 end
  self.idleStep = step
  local side, code = pick[1], pick[2]
  local address = ACTOR[side]
  -- 8411FF1C's prologue, then 8411F90C (8410B104, family 31)
  self.idleDispatch = true
  self:newFamily(address)
  self.idleDispatch = nil
  local m = self.cam.mem
  m:setU16(RECORD + 4, code)
  self.cam:setTimer(0x64)
  self.idleTimer = true -- the idle cycle's timer never holds the battle
  self.cam:endSplit()
  local family = self.cam:idleState(address)
  if family == 1 then
    -- Dispatch_008: the timer 0x12C until Dispatch_009 ends it
    self.cam:setTimer(0x12C)
    self.idleFamily1 = { actor = address, frame = 0 }
  end
end

-- A Pokemon faints: 8411A544's camera part (event 0x1C on its side).
function StadiumCamera:faint(scene, side)
  local address = ACTOR[side]
  if not address then return end
  self:sync(scene)
  self:newFamily(address)
  self.cam.mem:setU16(RECORD + 4, 0x1C)
  self.cam:faintState(address)
end

-- A new state family for an actor (841125F4) ends its running send-out.
-- Every event goes through 8411FF1C, which (when the record's new-event
-- flag +2 is set, 8411FE80) first ends the camera jolt (8410B578(0)) and
-- restarts the event timer (8411FEE8(100)) before giving the actor its
-- family; newFamily is that entry for every controller event.
function StadiumCamera:newFamily(address)
  -- any other event ends the wait for an attack (its held hit is dropped)
  self.attacking, self.heldHit = nil, nil
  if not self.idleDispatch then
    -- 841358B0: a new record starts with its own timer (+6), not what the
    -- idle cycle left in the previous one
    if self.idleTimer then self.cam:setTimer(0) end
    self.idleTimer = nil
  end
  self.cam:setJolt(0)
  self.firstMoverPending = nil -- a newer event replaces a waiting 0x5B
  if not self.idleDispatch then self.idle, self.idleFamily1 = nil, nil end
  self.victory = nil
  if address == ACTOR.player or address == nil then self:cutIntro() end
  if self.sendingOut and (address == nil or self.sendingOut.actor == address) then
    self.sendingOut = nil
  end
  if self.timed then
    for actor in pairs(self.timed) do
      if address == nil or actor == address then self.timed[actor] = nil end
    end
  end
  if self.runs then
    for actor in pairs(self.runs) do
      if address == nil or actor == address then self.runs[actor] = nil end
    end
  end
end

-- A Pokemon is sent out: 8411BB04's camera part now, then 8411BCC8's
-- frames from update (the actor's frame counter starts at 1).
function StadiumCamera:sendOut(scene, side)
  local address = ACTOR[side]
  if not address then return end
  self.idleStep = 0 -- 84135808: a send-out record restarts the idle cycle
  self.transformed[side] = nil
  if self.openingPhase then
    -- the battle's opening (84133714 with D_841951F0 + 0x9C7 set: event
    -- 0x22): family 24 films both Pokemon from the player's send-out, so the
    -- foe's send-out before it keeps the arena intro going
    if side ~= "player" then return end
    self.openingPhase = nil
    -- Stadium's engine waits for the arena intro before the opening
    if self.intro then self.pendingOpening = true; return end
    self.wildIntro = nil
    return self:openingSendOut(scene)
  end
  self:sync(scene)
  self:newFamily(address)
  self.cam:sendOutStart(address)
  self.sendingOut = { actor = address, frame = 1 }
end

function StadiumCamera:update(scene, dt)
  if not self.started then self:start(scene) end
  self.accumulator = self.accumulator + math.max(0, tonumber(dt) or 0)
  local steps = 0
  while self.accumulator >= StadiumCamera.TICK and steps < 4 do
    self.accumulator = self.accumulator - StadiumCamera.TICK
    self:sync(scene)
    -- the actors' states run before the camera (84112648, then 84111774)
    local out = self.sendingOut
    if out then
      if self.cam:sendOutFrame(out.actor, out.frame) then self.sendingOut = nil
      else out.frame = out.frame + 1 end
    end
    local due = {}
    for actor, t in pairs(self.timed) do
      t.frame = t.frame + 1
      if t.frame == t.at then due[#due + 1] = actor end
    end
    for _, actor in ipairs(due) do
      local t = self.timed[actor]
      self.timed[actor] = nil
      t.run(actor)
    end
    -- 8411FEFC: the event timer counts down
    local m = self.cam.mem
    local timer = m:u16(RECORD + 6)
    if timer > 0 then m:setU16(RECORD + 6, timer - 1) end
    local f1 = self.idleFamily1
    if f1 then
      f1.frame = f1.frame + 1
      local cap = m:s16(f1.actor + 0x1A) == 0xFC and 0x3C or StadiumCamera.FAMILY1_CAP
      if f1.frame >= cap then self.cam:setTimer(0); self.idleFamily1 = nil end
    end
    -- 8413543C: an idle record whenever nothing else plays, which is while
    -- the battle waits for a command (the host's command menus)
    local waiting = scene and type(scene.stadiumAwaitingCommand) == "function"
      and scene:stadiumAwaitingCommand()
    if self.firstMoverPending then
      if waiting then
        self.firstMoverPending = nil -- the turn is already over on the host
      elseif m:u16(RECORD + 6) == 0 then
        local side = scene and type(scene.stadiumFirstMover) == "function" and scene:stadiumFirstMover()
        if ACTOR[side] then self:firstMover(scene, side) end
      end
    end
    if waiting and not self.opening and not self.intro and m:u16(RECORD + 6) == 0 then
      self.idle = self.idle or {}
      self:nextIdle(scene)
    elseif not waiting then
      self.idle = nil
    end
    for actor, run in pairs(self.runs) do
      m:setU16(actor + 0x7E8, (m:s16(actor + 0x7E8) + 1) % 0x10000)
      if run.step(scene, SIDE_OF[actor]) then self.runs[actor] = nil end
    end
    local victory = self.victory
    if victory then
      m:setU16(victory.actor + 0x7E8, (m:s16(victory.actor + 0x7E8) + 1) % 0x10000)
      victory.substate = self.cam:victoryFrame(victory.actor, victory.substate)
      if victory.substate == 2 then self.victory = nil end
    end
    local opening = self.opening
    if opening then
      local m = self.cam.mem
      m:setU16(ACTOR.player + 0x7E8, (m:s16(ACTOR.player + 0x7E8) + 1) % 0x10000)
      local before = opening.substate
      opening.substate = self.cam:openingFrame(opening.substate,
        entranceEnded(scene, "player"), entranceEnded(scene, "enemy"))
      -- 8411C418 substate 1's end (8411C4C8): 84111C1C clears the effects
      if before == 1 and opening.substate == 2 and scene and type(scene.battleFxClear) == "function" then
        pcall(scene.battleFxClear, scene)
      end
      -- 8411C418 substate 4 at frame 0x28: 84112158(foe, 0xFC), the foe's
      -- entrance animation (substate 5 then waits for it to end)
      if before == 4 and opening.substate == 5 then
        self.foeEntranceReleased = true
        releaseEntrance(scene, "enemy")
      end
      if opening.substate == 6 then releaseEntrance(scene, "player"); releaseEntrance(scene, "enemy") end
      -- 8411C418 substate 2: 8410890C(0x124) on the foe when controller
      -- 1's width reaches 30 (not for a wild foe: nothing was thrown)
      if opening.substate == 2 and m:s16(C1 + 0x9E) == 30 and not self.wildBattle then
        signalEffect(scene, 0x124, "enemy")
      end
      if opening.substate == 6 then self.opening = nil end
    end
    local intro = self.intro
    if intro then
      intro.frame = intro.frame + 1
      -- Dispatch_184 (the tick after 8411C8A0): 8410890C(0x112) on the actor
      if intro.frame == 1 then signalEffect(scene, 0x112, "player") end
      self.cam.mem:setU16(ACTOR.player + 0x7E8, intro.frame)
      intro.substate = self.cam:arenaIntroFrame(intro.substate)
      if intro.substate == 3 then
        self.intro = nil
        -- the engine waited for the intro: the opening send-out follows
        if self.pendingOpening then self.pendingOpening = nil; self:openingSendOut(scene) end
      end
    end
    local wild = self.wildIntro
    if wild then
      wild.frame = wild.frame + 1
      if wild.frame == StadiumCamera.WILD_CLOSEUP then
        self.cam:setProgram(ACTOR.enemy, 4)
        self.wildIntro = nil
      end
    end
    self.cam:tick(GC0, GC1)
    steps = steps + 1
  end
  if steps == 4 then self.accumulator = 0 end
end

-- A pose outside the GeoCamera's far plane (6400, 8410B2DC) or not finite
-- cannot be drawn; the last drawable pose is kept and it is reported. This
-- is the port's safety net, not ROM behaviour: program 7 reads the species
-- offset row's first word as a float, and for 88 species that word is out of
-- range (see battle-camera.md).
StadiumCamera.POSE_LIMIT = 6400
local function drawable(pose)
  for _, v in ipairs({ pose.eye, pose.focus }) do
    for k = 1, 3 do
      local x = v[k]
      if x ~= x or math.abs(x) > StadiumCamera.POSE_LIMIT then return false end
    end
  end
  return pose.fov == pose.fov
end

-- The side Stadium hides for the current shot: program 14 (the over-the-
-- shoulder idle shot) runs on an actor 84120E14 hid (+1 bit 0 clear, via
-- 8411EE74), with the eye at that actor. nil otherwise.
function StadiumCamera:hiddenSide()
  local m = self.cam.mem
  for i = 0, 6 do
    local handler = m:u32(C0 + 8 + i * 8)
    if handler == 0x8410F0D0 or handler == 0x8411047C then
      local owner = m:u32(C0 + 4 + i * 8)
      if SIDE_OF[owner] and bit.band(m:u8(owner + 1), 1) == 0 then return SIDE_OF[owner] end
    end
  end
  return nil
end

-- The drawn views (GeoCamera +1 bit 0x10) with their controllers'
-- rectangles in the game's 320 x 240 screen: one full-screen view, or two
-- during the split-screen intro. Each view keeps its last drawable pose.
function StadiumCamera:views()
  local m = self.cam.mem
  local out = {}
  self.lastViewPose = self.lastViewPose or {}
  for i, v in ipairs({ { GC0, C0 }, { GC1, C1 } }) do
    local gc, ctrl = v[1], v[2]
    if bit.band(m:u8(gc + 1), Native.VIEW_DRAWN) ~= 0 then
      local pose = { eye = m:vec(gc + 0xA8), focus = m:vec(gc + 0xB4), up = m:vec(gc + 0xC0),
        fov = m:f32(gc + 0x2C),
        viewport = { m:s16(ctrl + 0x9A), m:s16(ctrl + 0x9C), m:s16(ctrl + 0x9E), m:s16(ctrl + 0xA0) } }
      if drawable(pose) then self.lastViewPose[i] = pose
      else
        self:report("pose", "battle camera: the ROM camera left the arena; the last drawable pose is kept")
        pose = self.lastViewPose[i] or pose
      end
      if pose.viewport[3] > 0 and pose.viewport[4] > 0 then out[#out + 1] = pose end
    end
  end
  if #out == 0 then
    local pose = self:pose()
    pose.viewport = { 0, 0, 0x140, 0xF0 }
    out[1] = pose
  end
  return out
end

-- GeoCamera 0 as eye / target / up / FOV (degrees), Stadium units.
function StadiumCamera:pose()
  local m = self.cam.mem
  local pose = { eye = m:vec(GC0 + 0xA8), focus = m:vec(GC0 + 0xB4), up = m:vec(GC0 + 0xC0),
    fov = m:f32(GC0 + 0x2C) }
  if drawable(pose) then self.lastPose = pose return pose end
  self:report("pose", "battle camera: the ROM camera left the arena (" .. string.format("%.3g, %.3g, %.3g",
    pose.focus[1], pose.focus[2], pose.focus[3]) .. "); the last drawable pose is kept")
  return self.lastPose or pose
end

-- The ROM data the camera needs, from the engine-managed Stadium 2 ROM and
-- the cached battle-FX catalog (fragment 79). nil plus a reason if missing.
function StadiumCamera.assets()
  if StadiumCamera.cachedAssets then return StadiumCamera.cachedAssets end
  local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")
  local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
  local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
  local candidate = Discovery.find()
  if not candidate then return nil, "the Stadium 2 ROM is unavailable" end
  local bytes, err = Discovery.read(candidate)
  if not bytes then return nil, err end
  local rom, order = Rom.normalise(bytes)
  if not rom then return nil, order end
  local catalog, catalogError = Importer.battleFxCatalog()
  local fragment = catalog and catalog.lifecycleAssets and catalog.lifecycleAssets.fragment79
  if not fragment then return nil, catalogError or "battle FX fragment 79 is unavailable" end
  -- only what the camera reads: main code (tables) and the camera records
  StadiumCamera.cachedAssets = { rom = rom:sub(1, 0xA8000), fragment79 = fragment,
    records = rom:sub(StadiumCamera.CAMERA_RECORDS + 1, StadiumCamera.CAMERA_RECORDS + StadiumCamera.ROWS * 0x30),
    motionBlobs = StadiumCamera.motionArchive(rom),
    speciesShots = rom:sub(0x49B780 + 0xE0A0 + 1, 0x49B780 + 0xE0A0 + 252 * 0x10),
    introPaths = Native.introPathBytes(rom, fragment),
    offsets = rom:sub(StadiumCamera.OFFSET_RECORDS + 1, StadiumCamera.OFFSET_RECORDS + StadiumCamera.ROWS * 0x20) }
  return StadiumCamera.cachedAssets
end

-- The scene's camera, created on first use (nil plus a reason when the ROM
-- data is missing; reported once by the caller).
-- 84135778: the next battle record loads only once the current one has
-- finished: its timer (+6) is 0 (the families set and clear it), and here
-- also no family that the port tracks without a timer (send-out, timed
-- states, runs) is still playing. The hosts hold
-- their own event queues on this (Scene:stadiumPresentationBusy). The
-- battle's opening and the arena intro wait on the hosts' send-outs
-- themselves, and the victory camera plays after the battle: none of them
-- hold the hosts. The idle cycle's timer never does either.
function StadiumCamera:busy()
  if self.opening or self.intro or self.openingPhase or self.pendingOpening
      or self.victory then
    return false
  end
  -- (a pending first mover is not: its side is known only once the host
  -- runs that action, so holding it would wait for itself; the 0x5A timer
  -- and the first mover's own timer cover the turn start)
  if self.attacking or self.sendingOut then return true end
  if next(self.timed or {}) ~= nil or next(self.runs or {}) ~= nil then return true end
  if self.idleTimer or self.idle then return false end
  return self.cam.mem:u16(RECORD + 6) > 0
end

function StadiumCamera.forScene(scene, warn)
  if scene.stadiumCamera then return scene.stadiumCamera end
  if scene.stadiumCameraError then return nil, scene.stadiumCameraError end
  local assets, err = StadiumCamera.assets()
  local camera
  if assets then
    camera, err = StadiumCamera.new({ rom = assets.rom, records = assets.records, offsets = assets.offsets,
      introPaths = assets.introPaths, motionBlobs = assets.motionBlobs, speciesShots = assets.speciesShots,
      fragment79 = assets.fragment79, warn = warn })
  end
  if not camera then scene.stadiumCameraError = err or "battle camera unavailable" return nil, err end
  scene.stadiumCamera = camera
  return camera
end

return StadiumCamera
