-- Draw-call batching for battle-FX particle shapes.
--
-- A particle-heavy effect draws the same small shape (usually one textured
-- quad) many times per frame. Drawing each one through Renderer:drawScene
-- costs a full shader setup (~50 uniform uploads) and a draw call per
-- particle, which mobile GPU drivers handle badly.
--
-- The batcher keeps the look exact by running the unchanged drawScene code
-- in a recording mode: its shader uploads and graphics-state calls are
-- captured instead of reaching the GPU. Consecutive recorded draws whose
-- complete state is identical, except for the per-particle values in
-- INSTANCE (transform, tint, primitive/environment colour, texture scroll),
-- are merged into one mesh. Positions are transformed on the CPU and the
-- per-particle values travel as vertex attributes (the shaders' fxInstanced
-- path). Draw order is preserved, so blending and depth results match the
-- sequential draws.
local Batch = {}
Batch.__index = Batch

local okFfi, ffi = pcall(require, "ffi")

-- Uniforms that may differ inside one merged draw.
local INSTANCE = {
  mvp = true, modelMatrix = true, sceneTint = true, primitiveColor = true,
  environmentColor = true, textureScroll = true,
}

local BASE_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexNormal", "float", 3 },
  { "VertexColor", "float", 4 },
  { "FxPrim", "float", 4 },
  { "FxEnv", "float", 4 },
  { "FxTint", "float", 4 },
  { "FxScroll", "float", 4 },
}
local FLOATS = 28
local IDENTITY = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }
local BATCHABLE_TIERS = { lit = true, ["mobile-simple"] = true }

function Batch.new()
  return setmetatable({
    cur = {}, curByShader = {}, dirty = {}, memo = {}, diverged = true, open = nil,
    capacity = 0, mesh = nil, stats = { batches = 0, instances = 0 },
  }, Batch)
end

-- Captured arguments of one shader send, kept per uniform name.
local function store(slot, n, a, b, c)
  slot.n, slot[1], slot[2], slot[3] = n, a, b, c
end

local function valueEqual(x, y)
  if x == y then return true end
  if type(x) ~= "table" or type(y) ~= "table" then return false end
  local n = #x
  if n ~= #y then return false end
  for i = 1, n do
    local u, v = x[i], y[i]
    if u ~= v then
      if type(u) == "table" and type(v) == "table" then
        if not valueEqual(u, v) then return false end
      else
        return false
      end
    end
  end
  return true
end

local function slotEqual(slot, n, a, b, c)
  return slot ~= nil and slot.n == n and valueEqual(slot[1], a)
    and valueEqual(slot[2], b) and valueEqual(slot[3], c)
end

-- Renderers the recorder reproduces exactly: effect shapes on the two
-- shaders with per-particle attributes, with no Pokemon-only extras.
function Batch.supports(renderer, options)
  if type(renderer) ~= "table" or not renderer.shader then return false end
  if not BATCHABLE_TIERS[renderer.shaderTier] then return false end
  if options and options.screenSpace then return false end
  if renderer.debugOnlyPrimitive then return false end
  local model = renderer.model
  if not (model and model.battleFx == true) then return false end
  if renderer.fxBatchSupported == nil then
    local ok = type(renderer.parts) == "table"
    for _, part in ipairs(renderer.parts or {}) do
      if not (part.rows and part.prim and part.prim.idx) or part.prim.effect == "fire" then
        ok = false
        break
      end
    end
    renderer.fxBatchSupported = ok
  end
  if not renderer.fxBatchSupported then return false end
  local dynamic = renderer.handlerState and renderer.handlerState.dynamicObjectsBySite
  if type(dynamic) == "table" and next(dynamic) ~= nil then return false end
  return true
end

local function partForMesh(renderer, mesh)
  local map = renderer.fxBatchPartByMesh
  local part = map and map[mesh]
  if part and part.mesh == mesh then return part end
  -- Parts can rebuild their meshes; refresh the lookup on a miss.
  map = {}
  for _, candidate in ipairs(renderer.parts or {}) do
    if candidate.mesh then map[candidate.mesh] = candidate end
  end
  renderer.fxBatchPartByMesh = map
  return map[mesh]
end

function Batch:_send(name, n, a, b, c)
  local cur = self.cur
  local slot = cur[name]
  if not slot then slot = {}; cur[name] = slot end
  store(slot, n, a, b, c)
  local sent = self.sent
  if sent then
    local copy = sent[name]
    if not copy then copy = {}; sent[name] = copy end
    store(copy, n, a, b, c)
  end
  -- Only the value in effect at the draw matters: drawScene resets some
  -- uniforms before setting the real value, so compare at draw time.
  if self.open and not INSTANCE[name] then self.dirty[name] = true end
end

local function textureState(texture)
  if not texture then return nil end
  local state = { texture = texture }
  if texture.getWrap then state.ws, state.wt = texture:getWrap() end
  if texture.getFilter then state.fmin, state.fmag, state.anis = texture:getFilter() end
  return state
end

local function textureStateEqual(x, y)
  if x == y then return true end
  if not x or not y then return false end
  return x.texture == y.texture and x.ws == y.ws and x.wt == y.wt
    and x.fmin == y.fmin and x.fmag == y.fmag and x.anis == y.anis
end

local function graphicsEqual(x, y)
  return x.blend == y.blend and x.alphaMode == y.alphaMode
    and x.compare == y.compare and x.write == y.write and x.cull == y.cull
    and x.r == y.r and x.g == y.g and x.b == y.b and x.a == y.a
end

function Batch:_ensureCapacity(vertices)
  if self.capacity >= vertices and self.mesh then return true end
  local capacity = math.max(256, self.capacity)
  while capacity < vertices do capacity = capacity * 2 end
  local ok, mesh = pcall(love.graphics.newMesh, BASE_FORMAT, capacity, "triangles", "stream")
  if not ok or not mesh then return false end
  if self.mesh and self.mesh.release then self.mesh:release() end
  self.mesh, self.capacity = mesh, capacity
  if okFfi then
    local data = love.data.newByteData(capacity * FLOATS * 4)
    local floats = ffi.cast("float*", data:getFFIPointer())
    -- Vertices already written for the open batch move to the new buffer.
    local used = self.open and self.open.count or 0
    if self.floats and used > 0 then ffi.copy(floats, self.floats, used * FLOATS * 4) end
    self.data, self.floats = data, floats
  else
    self.rows = self.rows or {}
  end
  return true
end

-- Appends one draw of `part` under matrix `m` (row-major) with the current
-- instance uniforms.
-- The instance values of the draw being recorded (current uniform values).
function Batch:_instance()
  local cur = self.cur
  return cur.primitiveColor and cur.primitiveColor[1] or IDENTITY,
    cur.environmentColor and cur.environmentColor[1] or IDENTITY,
    cur.sceneTint and cur.sceneTint[1] or IDENTITY,
    cur.textureScroll and cur.textureScroll[1] or IDENTITY
end

function Batch:_append(part, m, prim, env, tint, scroll)
  local open = self.open
  local rows = part.rows
  local map = part.drawMap or part.prim.idx
  local count = #map
  local p1, p2, p3, p4 = prim[1] or 1, prim[2] or 1, prim[3] or 1, prim[4] or 1
  local e1, e2, e3, e4 = env[1] or 1, env[2] or 1, env[3] or 1, env[4] or 1
  local t1, t2, t3, t4 = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
  local s1, s2, s3, s4 = scroll[1] or 0, scroll[2] or 0, scroll[3] or 0, scroll[4] or 0
  local m1, m2, m3, m4 = m[1], m[2], m[3], m[4]
  local m5, m6, m7, m8 = m[5], m[6], m[7], m[8]
  local m9, m10, m11, m12 = m[9], m[10], m[11], m[12]
  local start = open.count
  if not self:_ensureCapacity(start + count) then return false end
  local f = self.floats
  for k = 1, count do
    local row = rows[map[k]]
    local x, y, z = row[1], row[2], row[3]
    if f then
      local o = (start + k - 1) * FLOATS
      f[o] = m1 * x + m2 * y + m3 * z + m4
      f[o + 1] = m5 * x + m6 * y + m7 * z + m8
      f[o + 2] = m9 * x + m10 * y + m11 * z + m12
      f[o + 3], f[o + 4] = row[4], row[5]
      f[o + 5], f[o + 6], f[o + 7] = row[6], row[7], row[8]
      f[o + 8], f[o + 9], f[o + 10], f[o + 11] = row[9], row[10], row[11], row[12]
      f[o + 12], f[o + 13], f[o + 14], f[o + 15] = p1, p2, p3, p4
      f[o + 16], f[o + 17], f[o + 18], f[o + 19] = e1, e2, e3, e4
      f[o + 20], f[o + 21], f[o + 22], f[o + 23] = t1, t2, t3, t4
      f[o + 24], f[o + 25], f[o + 26], f[o + 27] = s1, s2, s3, s4
    else
      local r = self.rows[start + k]
      if not r then r = {}; self.rows[start + k] = r end
      r[1] = m1 * x + m2 * y + m3 * z + m4
      r[2] = m5 * x + m6 * y + m7 * z + m8
      r[3] = m9 * x + m10 * y + m11 * z + m12
      r[4], r[5], r[6], r[7], r[8] = row[4], row[5], row[6], row[7], row[8]
      r[9], r[10], r[11], r[12] = row[9], row[10], row[11], row[12]
      r[13], r[14], r[15], r[16] = p1, p2, p3, p4
      r[17], r[18], r[19], r[20] = e1, e2, e3, e4
      r[21], r[22], r[23], r[24] = t1, t2, t3, t4
      r[25], r[26], r[27], r[28] = s1, s2, s3, s4
    end
  end
  open.count = start + count
  open.instances = open.instances + 1
  return true
end

function Batch:_onDraw(renderer, mesh, vp, matrix)
  local part = partForMesh(renderer, mesh)
  local texture = mesh.getTexture and mesh:getTexture() or nil
  local gstate = self.gstate
  local open = self.open
  local tstate = open and open.texture and open.texture.texture == texture
    and open.texture or textureState(texture)
  if open and not self.diverged then
    local ref, cur = open.ref, self.cur
    for name in pairs(self.dirty) do
      local slot = cur[name]
      if not slot or not slotEqual(ref[name], slot.n, slot[1], slot[2], slot[3]) then
        self.diverged = true
        break
      end
    end
  end
  for name in pairs(self.dirty) do self.dirty[name] = nil end
  local prim, env, tint, scroll = self:_instance()
  if open and not self.diverged and open.shader == self.realShader
      and graphicsEqual(open.graphics, gstate)
      and textureStateEqual(open.texture, tstate) then
    self:_append(part, matrix, prim, env, tint, scroll)
    self:_remember(part, open.token, prim, env, tint, scroll)
    return
  end
  self:flush()
  -- Sent values are fresh tables from drawScene and are never modified
  -- afterwards; the reference keeps its own slots but shares the values.
  local ref = {}
  for name, slot in pairs(self.cur) do
    ref[name] = { n = slot.n, slot[1], slot[2], slot[3] }
  end
  local graphics = {}
  for k, v in pairs(gstate) do graphics[k] = v end
  local token = { shader = self.realShader, ref = ref, graphics = graphics, texture = tstate }
  self:_open(token, vp)
  self:_append(part, matrix, prim, env, tint, scroll)
  self:_remember(part, token, prim, env, tint, scroll)
end

function Batch:_open(token, vp)
  self.open = { shader = token.shader, ref = token.ref, graphics = token.graphics,
    texture = token.texture, token = token, vp = vp, count = 0, instances = 0 }
  self.diverged = false
end

-- A fresh memoised recording keeps each draw, with that draw's own
-- per-particle values (each part of a shape can send different ones).
function Batch:_remember(part, token, prim, env, tint, scroll)
  local draws = self.recordingDraws
  if draws then
    draws[#draws + 1] = { part = part, token = token, prim = prim, env = env,
      tint = tint, scroll = scroll }
  end
end

-- Memo key: everything drawScene reads that can differ between packets of
-- one renderer in a frame (Player supplies it as `inputs`).
local function sameColor(x, y)
  if x == y then return true end
  if type(x) ~= "table" or type(y) ~= "table" then return false end
  return x[1] == y[1] and x[2] == y[2] and x[3] == y[3] and x[4] == y[4]
end

local function sameInputs(entry, inputs)
  return entry.frame == inputs.frame and entry.pose == inputs.pose
    and entry.cull == inputs.cull and entry.colors == (inputs.colors ~= nil)
    and sameColor(entry.tint, inputs.tint) and sameColor(entry.primary, inputs.primary)
    and sameColor(entry.secondary, inputs.secondary)
end

local function colorCopy(c)
  if type(c) ~= "table" then return c end
  return { c[1], c[2], c[3], c[4] }
end

-- Replays a memoised recording under this particle's matrix: the same
-- uniform values and draws drawScene produced for identical inputs.
function Batch:_replay(entry, matrix, vp)
  local cur = self.curByShader[entry.shader]
  if not cur then cur = {}; self.curByShader[entry.shader] = cur end
  self.cur = cur
  for name, slot in pairs(entry.sends) do
    local target = cur[name]
    if not target then target = {}; cur[name] = target end
    store(target, slot.n, slot[1], slot[2], slot[3])
  end
  local draws = entry.draws
  for i = 1, #draws do
    local draw = draws[i]
    local open = self.open
    if not (open and open.token == draw.token and not self.diverged) then
      self:flush()
      self:_open(draw.token, vp)
    end
    self:_append(draw.part, matrix, draw.prim, draw.env, draw.tint, draw.scroll)
  end
  for name in pairs(self.dirty) do self.dirty[name] = nil end
end

-- Records renderer:drawScene(pass, matrix, options) into the batch.
-- `inputs` (optional) lets a later particle with identical inputs replay
-- this recording instead of running drawScene again.
function Batch:record(renderer, pass, matrix, options, inputs)
  local list
  if inputs then
    local byRenderer = self.memo[renderer]
    if not byRenderer then byRenderer = {}; self.memo[renderer] = byRenderer end
    list = byRenderer[pass]
    if not list then list = {}; byRenderer[pass] = list end
    for i = 1, #list do
      if sameInputs(list[i], inputs) then
        self:_replay(list[i], matrix, options and options.viewProjection)
        return true
      end
    end
  end
  local g = love.graphics
  local saved = { setShader = g.setShader, setColor = g.setColor,
    setDepthMode = g.setDepthMode, setBlendMode = g.setBlendMode,
    setMeshCullMode = g.setMeshCullMode, draw = g.draw }
  -- flush() can run mid-recording and must reach the real graphics calls.
  self.realGraphics = saved
  local realShader = renderer.shader
  self.realShader = realShader
  self.lastShader = realShader
  -- Recorded uniform values belong to the shader object they were sent to.
  local cur = self.curByShader[realShader]
  if not cur then cur = {}; self.curByShader[realShader] = cur end
  self.cur = cur
  self.gstate = self.gstate or {}
  local gstate = self.gstate
  gstate.r, gstate.g, gstate.b, gstate.a = 1, 1, 1, 1
  local vp = options and options.viewProjection
  local recorder = self
  local proxy = { send = function(_, name, a, b, c)
    recorder:_send(name, select("#", a, b, c), a, b, c)
    return true
  end }
  g.setShader = function() end
  g.setColor = function(r, gg, b, a)
    gstate.r, gstate.g, gstate.b, gstate.a = r, gg, b, a
  end
  g.setDepthMode = function(compare, write) gstate.compare, gstate.write = compare, write end
  g.setBlendMode = function(mode, alpha) gstate.blend, gstate.alphaMode = mode, alpha end
  g.setMeshCullMode = function(mode) gstate.cull = mode end
  local drawError
  g.draw = function(mesh)
    if not partForMesh(renderer, mesh) then
      drawError = "unrecognised mesh"
      return
    end
    recorder:_onDraw(renderer, mesh, vp, matrix)
  end
  renderer.shader = proxy
  local draws = list and {} or nil
  self.recordingDraws, self.sent = draws, list and {} or nil
  local ok, result, message = pcall(renderer.drawScene, renderer, pass, matrix, options)
  local sent = self.sent
  self.recordingDraws, self.sent = nil, nil
  renderer.shader = realShader
  for name, fn in pairs(saved) do g[name] = fn end
  self.realGraphics = nil
  if not ok then return false, tostring(result) end
  if result == false then return false, message end
  if drawError then return false, drawError end
  if list then
    list[#list + 1] = { frame = inputs.frame, pose = inputs.pose, cull = inputs.cull,
      colors = inputs.colors ~= nil, tint = colorCopy(inputs.tint),
      primary = colorCopy(inputs.primary), secondary = colorCopy(inputs.secondary),
      shader = realShader, sends = sent, draws = draws }
  end
  return true
end

-- Draws the pending merged batch.
function Batch:flush()
  local open = self.open
  self.open = nil
  self.diverged = true
  if not open or open.count == 0 then return end
  local g = self.realGraphics or love.graphics
  local shader = open.shader
  g.setShader(shader)
  for name, slot in pairs(open.ref) do
    if name ~= "mvp" and name ~= "modelMatrix" then
      pcall(shader.send, shader, name, slot[1], slot[2], slot[3])
    end
  end
  pcall(shader.send, shader, "mvp", "row", open.vp or IDENTITY)
  pcall(shader.send, shader, "modelMatrix", "row", IDENTITY)
  pcall(shader.send, shader, "fxInstanced", 1)
  local gs = open.graphics
  if gs.blend then g.setBlendMode(gs.blend, gs.alphaMode) end
  if gs.compare then g.setDepthMode(gs.compare, gs.write) end
  if gs.cull then g.setMeshCullMode(gs.cull) end
  g.setColor(gs.r or 1, gs.g or 1, gs.b or 1, gs.a or 1)
  local mesh = self.mesh
  if self.floats then
    mesh:setVertices(self.data, 1, open.count)
  else
    for i = open.count + 1, #self.rows do self.rows[i] = nil end
    mesh:setVertices(self.rows)
  end
  local t = open.texture
  if t and t.texture then
    if t.ws and t.texture.setWrap then pcall(t.texture.setWrap, t.texture, t.ws, t.wt) end
    if t.fmin and t.texture.setFilter then
      pcall(t.texture.setFilter, t.texture, t.fmin, t.fmag, t.anis)
    end
    mesh:setTexture(t.texture)
  else
    mesh:setTexture()
  end
  mesh:setDrawRange(1, open.count)
  g.draw(mesh)
  pcall(shader.send, shader, "fxInstanced", 0)
  self.stats.batches = self.stats.batches + 1
  self.stats.instances = self.stats.instances + open.instances
end

-- Draws what is pending, then leaves every recorded shader with the uniform
-- values sequential drawing would have left (the latest value of each
-- uniform). Later draws that rely on an inherited value (the Pokemon models
-- share these shaders) then see exactly what they saw before batching.
function Batch:settle()
  self:flush()
  for shader, cur in pairs(self.curByShader) do
    for name, slot in pairs(cur) do
      pcall(shader.send, shader, name, slot[1], slot[2], slot[3])
    end
    pcall(shader.send, shader, "fxInstanced", 0)
  end
  -- Likewise the graphics state the last recorded draw code left behind.
  local gs = self.gstate
  if gs and next(self.curByShader) ~= nil then
    local g = self.realGraphics or love.graphics
    if gs.blend then g.setBlendMode(gs.blend, gs.alphaMode) end
    if gs.compare then g.setDepthMode(gs.compare, gs.write) end
    if gs.cull then g.setMeshCullMode(gs.cull) end
    if gs.r then g.setColor(gs.r, gs.g, gs.b, gs.a) end
    if self.lastShader then g.setShader(self.lastShader) end
  end
end

-- Ends the frame: draws what is pending and forgets the recorded state.
function Batch:finish()
  self:settle()
  self.cur, self.curByShader, self.memo = {}, {}, {}
end

function Batch:release()
  self.open = nil
  if self.mesh and self.mesh.release then self.mesh:release() end
  self.mesh, self.capacity, self.data, self.floats, self.rows = nil, 0, nil, nil, nil
end

return Batch
