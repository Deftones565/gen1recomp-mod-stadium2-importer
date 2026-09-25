-- Direct battle-FX shape transforms (84102B3C geometry modes) and per-entry
-- render modes (84102E84). Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local RenderMode = require(prefix .. "stadium2_battle_fx_render_mode")
local Packets = require(prefix .. "stadium2_battle_fx_draw_packets")
local Player = require(prefix .. "stadium2_battle_fx_player")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-5) end

-- 84102E84 render-mode words and their decoded blend/depth state.
local expected = {
  [0x06] = {0x0C184240, "blend", false, false},
  [0x46] = {0x0C1841C8, "blend", false, false},
  [0x86] = {0x0C184A50, "blend", true, false},
  [0xC6] = {0x0C1849D8, "blend", true, false},
  [0x04] = {0x0F0A7008, "cutout", false, false},
  [0x44] = {0x0C193048, "cutout", false, false},
  [0x84] = {0x0C193078, "cutout", true, true},
  [0xC4] = {0x0C193078, "cutout", true, true},
  [0x01] = {0x0F0A4000, "opaque", false, false},
  [0x41] = {0x0C192048, "opaque", false, false},
  [0x81] = {0x0C192230, "opaque", true, true},
  [0xC1] = {0x0C192078, "opaque", true, true},
  [0x00] = {0x0C184240, "blend", false, false},
  [0x85] = {0x0C184240, "blend", false, false},
}
for state, row in pairs(expected) do
  local mode = RenderMode.decode(state)
  ok(mode.word == row[1], ("render state 0x%02X selects 0x%08X"):format(state, row[1]))
  ok(mode.blend == row[2] and mode.depthCompare == row[3]
    and mode.depthWrite == row[4], ("render state 0x%02X decodes blend/depth"):format(state))
end
ok(RenderMode.decode(0x3F).ownerTexture == true, "low 0x3F selects the owner texture path")
ok(RenderMode.decode(nil) == nil, "missing render state stays undecoded")

-- Synthetic 4096-entry sin/cos tables with the ROM index contract.
local tables = {tableA = {}, tableB = {}}
for i = 0, 4095 do
  tables.tableA[i + 1] = math.sin(i * 2 * math.pi / 4096)
  tables.tableB[i + 1] = math.cos(i * 2 * math.pi / 4096)
end
local function trig(angle)
  local i = math.floor(angle % 65536 / 16)
  return tables.tableA[i + 1], tables.tableB[i + 1]
end
local function mul3(a, b)
  local out = {}
  for r = 1, 3 do
    out[r] = {}
    for c = 1, 3 do
      out[r][c] = a[r][1] * b[1][c] + a[r][2] * b[2][c] + a[r][3] * b[3][c]
    end
  end
  return out
end
-- Column j of the renderer matrix is native row j.
local function nativeRow(m, j) return {m[j], m[4 + j], m[8 + j]} end

local rotation = {0x1234, 0x5678, 0x9ABC}
local transform = {position = {3, 4, 5}, nativeScale = 2, worldScale = 1,
  rotation = rotation}
local sx, cx = trig(rotation[1])
local sy, cy = trig(rotation[2])
local sz, cz = trig(rotation[3])
-- Row-vector composition Rz * Rx * Ry, built independently of the module.
local rz = {{cz, sz, 0}, {-sz, cz, 0}, {0, 0, 1}}
local rx = {{1, 0, 0}, {0, cx, sx}, {0, -sx, cx}}
local ry = {{cy, 0, -sy}, {0, 1, 0}, {sy, 0, cy}}
local reference = mul3(mul3(rz, rx), ry)
for _, mode in ipairs({0, 2}) do
  local m = assert(Packets.shapeMatrix(transform, mode, {trigTables = tables}))
  for row = 1, 3 do
    local scale = (mode == 0 or row == 2) and 2 or 1
    local got = nativeRow(m, row)
    for c = 1, 3 do
      ok(near(got[c], reference[row][c] * scale),
        ("mode %d row %d column %d follows 84103A3C/84103BCC"):format(mode, row, c))
    end
  end
  ok(m[4] == 3 and m[8] == 4 and m[12] == 5, "translation uses +0x20..+0x28")
end
local missingTrig, code = Packets.shapeMatrix(transform, 0, {})
ok(missingTrig == nil and code == "unresolved-shape-trig", "missing ROM angle tables are diagnosed")

-- Billboards: view rotation times the object basis must be (rotated) s*I.
local camera = {eye = {7, 9, 20}, focus = {-2, 1, 0}, up = {0, 1, 0}}
local function normalize(v)
  local l = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
  return {v[1] / l, v[2] / l, v[3] / l}
end
local function cross(a, b)
  return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]}
end
local back = normalize({camera.eye[1] - camera.focus[1], camera.eye[2] - camera.focus[2],
  camera.eye[3] - camera.focus[3]})
local right = normalize(cross(camera.up, back))
local up = cross(back, right)
local view = {right, up, back} -- world -> eye rotation rows
local function eyeBasis(m)
  local out = {}
  for axis = 1, 3 do
    local col = nativeRow(m, axis)
    out[axis] = {}
    for r = 1, 3 do
      out[axis][r] = view[r][1] * col[1] + view[r][2] * col[2] + view[r][3] * col[3]
    end
  end
  return out
end
local billboard = assert(Packets.shapeMatrix(transform, 1, {camera = camera}))
local basis = eyeBasis(billboard)
for axis = 1, 3 do
  for r = 1, 3 do
    ok(near(basis[axis][r], axis == r and 2 or 0), "mode 1 faces the camera (84104528)")
  end
end
local st, ct = trig(rotation[3])
for _, mode in ipairs({3, 4}) do
  local m = assert(Packets.shapeMatrix(transform, mode, {camera = camera, trigTables = tables}))
  local b = eyeBasis(m)
  local xs = mode == 4 and 2 or 1
  ok(near(b[1][1], ct * xs) and near(b[1][2], st * xs) and near(b[1][3], 0),
    ("mode %d rotates the camera X axis by +0x6E"):format(mode))
  ok(near(b[2][1], -st * 2) and near(b[2][2], ct * 2) and near(b[2][3], 0),
    ("mode %d scales the rotated camera Y axis"):format(mode))
  ok(near(b[3][3], xs) and near(b[3][1], 0) and near(b[3][2], 0),
    ("mode %d keeps the camera Z axis"):format(mode))
end
local noCamera, cameraCode = Packets.shapeMatrix(transform, 1, {trigTables = tables})
ok(noCamera == nil and cameraCode == "unresolved-billboard-camera", "missing camera is diagnosed")
local screen, screenCode = Packets.shapeMatrix(transform, 5, {trigTables = tables})
ok(screen == nil and screenCode == "unsupported-shape-geometry-mode", "screen modes stay on the overlay path")

-- Player selects the transform from the loaded shape model at draw time.
local particle = {id = 1, effectId = 1, age = 0, frame = 0, shapeId = 9,
  scale = {2, 2, 2}, rotation = rotation, event = {}, material = {shapeId = 9}}
local snapshot = {frame = 0, effects = {{id = 1, moveId = 1}}, particles = {particle}}
local drawn = {}
local shapeModel = {battleFxGeometryMode = 1, prims = {}}
local stub = {model = shapeModel, drawScene = function(_, pass, matrix)
  if pass == "opaque" then drawn[#drawn + 1] = matrix end
  return true
end}
local player = Player.new({runtime = {snapshot = function() return snapshot end,
    catalog = {trigTables = tables}},
  loadRenderer = function() return stub end,
  resolvePlacement = function() return {resolved = true, position = {3, 4, 5}, scale = 1} end})
ok(player:draw({camera = camera}).drawn == 1, "billboard shape draws")
local drawnBasis = eyeBasis(drawn[#drawn])
ok(near(drawnBasis[1][1], 2) and near(drawnBasis[1][2], 0) and near(drawnBasis[2][2], 2),
  "Player passes the camera-facing matrix to the renderer")
shapeModel.battleFxCompiledLayout = true
player:draw({camera = camera})
local layoutMatrix = drawn[#drawn]
local modelSystem = Packets.nativeMatrix({3, 4, 5}, {2, 2, 2}, rotation)
local same = true
for i = 1, 16 do same = same and near(layoutMatrix[i], modelSystem[i]) end
ok(same, "compiled layouts keep the model-system transform (841028DC)")
shapeModel.battleFxCompiledLayout = nil
local result = player:draw({})
ok(result.drawn == 0, "billboard without camera does not draw")
local found = false
for _, d in ipairs(player.diagnostics) do
  if d.code == "unresolved-billboard-camera" then found = true end
end
ok(found, "billboard without camera reports a diagnostic")

-- ROM-backed: every direct shape reachable from entries 1..301 decodes, and
-- the real renderer applies its depth/blend state.
local path = os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(path, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1", "required ROM unavailable")
  print(checks .. " checks passed (battle FX shape transforms; ROM SKIP)")
  return
end
local rom = file:read("*a"); file:close()
local FxRom = require(prefix .. "stadium2_battle_fx_rom")
local Resources = require(prefix .. "stadium2_battle_fx_resources")
local catalog = assert(FxRom.catalog(rom))
local slice = rom:sub(Resources.ROM_START + 1, Resources.ROM_END)
local modes, states, samples = {}, {}, {}
for moveId = 1, 251 do
  local move = catalog.moves[moveId]
  local resources = Resources.resolve(slice, move.resources)
  for _, bank in ipairs({"primaryDispatch", "alternateDispatch"}) do
    for _, entry in ipairs(move[bank]) do
      for _, record in ipairs(entry.programId and catalog.programs[entry.programId].records or {}) do
        local event = record.emitter
        if resources and event and event.descriptorKind == "particle" and event.mode ~= 7 and event.shapeId then
          local shape = Resources.shapeFromResolved(resources, event.shapeId)
          if shape and not shape.compiledLayout then
            modes[shape.geometryMode] = true
            for _, e in ipairs(shape.entries) do
              local decoded = RenderMode.decode(e.renderState)
              assert(decoded and not decoded.ownerTexture, "retail FX entry uses a decoded render mode")
              states[e.renderState] = true
              local key = decoded.depthCompare and "depth" or "nodepth"
              samples[key] = samples[key] or {moveId, event.shapeId, resources}
            end
          end
        end
      end
    end
  end
end
for mode in pairs(modes) do ok(mode >= 0 and mode <= 4, "world particle shapes use geometry modes 0..4") end
ok(modes[1] and modes[4], "retail shapes include camera-facing billboards")
ok(samples.depth and samples.nodepth, "retail shapes include depth-tested and untested entries")

local calls = {}
_G.love = {graphics = {}}
local g = love.graphics
function g.newMesh(_, rows) return {rows = rows, setVertexMap = function() end,
  setVertices = function() end, setTexture = function() end, release = function() end} end
function g.newShader() return {send = function() end, release = function() end} end
function g.newImage() return {setFilter = function() end, setWrap = function() end, release = function() end} end
function g.setDepthMode(...) calls[#calls + 1] = {"depth", ...} end
function g.setBlendMode(...) calls[#calls + 1] = {"blend", ...} end
function g.setMeshCullMode() end
function g.setShader() end
function g.draw() calls[#calls + 1] = {"draw"} end
local Renderer = require(prefix .. "renderer")
for key, sample in pairs(samples) do
  local shape = assert(Resources.shapeFromResolved(sample[3], sample[2]))
  local model = assert(Resources.modelFromShape(shape, "shape-transform-" .. key))
  local renderer = assert(Renderer.new(model, {flipY = false}))
  for i = #calls, 1, -1 do calls[i] = nil end
  assert(renderer:drawScene("opaque", {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1},
    {viewProjection = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}}))
  local depth
  for i, call in ipairs(calls) do
    if call[1] == "draw" then
      for j = i - 1, 1, -1 do if calls[j][1] == "depth" then depth = calls[j]; break end end
      break
    end
  end
  local decoded = RenderMode.decode(model.prims[1].battleFxRenderState)
  ok(depth and (depth[2] == "always") == (not decoded.depthCompare),
    ("renderer applies 84102E84 depth compare (%s, move %d shape %d)"):format(key, sample[1], sample[2]))
  ok(depth and depth[3] == (decoded.depthWrite == true),
    ("renderer applies 84102E84 depth write (%s)"):format(key))
  renderer:release()
end
_G.love = nil
local stateCount = 0
for _ in pairs(states) do stateCount = stateCount + 1 end
print(("%d checks passed (battle FX shape transforms; %d retail render states)"):format(checks, stateCount))
