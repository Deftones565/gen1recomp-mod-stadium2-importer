-- Exhaustive ROM-to-renderer feature inventory for Stadium 2 battle fields.
-- Run from the gen1recomp root:
--   lua mods/STADIUM2_IMPORTER/tools/audit_stadium2_arena_parity.lua ROM.z64

package.path = "./?.lua;./?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
local Phase5 = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")

local path = (arg and arg[1]) or os.getenv("STADIUM2_ROM")
assert(path, "usage: audit_stadium2_arena_parity.lua <stadium2.z64>")

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(assert(file:read("*a"))))
file:close()
assert(#rom == Rom.SIZE and Rom.title(rom):upper() == Rom.US_TITLE,
  "expected the supported Pokemon Stadium 2 US ROM")
local archive = assert(Rom.archiveAt(rom, Rom.STADIUM_MODEL_TABLE_START))
assert(archive.count == Rom.STADIUM_MODEL_TABLE_RECORDS,
  "unexpected Stadium field archive")

local BASE = 0x8FF00000
local floor = math.floor
local function byte(data, offset)
  return type(offset) == "number" and data:byte(offset + 1) or nil
end
local function u32(data, offset)
  if type(offset) ~= "number" then return nil end
  local a, b, c, d = data:byte(offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end
local function inside(data, pointer, length)
  local offset = tonumber(pointer) and pointer - BASE or -1
  return offset >= 0 and offset + (length or 1) <= #data and offset or nil
end
local function bits(value, shift, width)
  return floor((tonumber(value) or 0) / 2 ^ shift) % 2 ^ width
end
local function key(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = tostring(value) end
  return table.concat(out, ",")
end
local function add(map, name, arena, amount)
  local row = map[name]
  if not row then row = { count = 0, arenas = {} }; map[name] = row end
  row.count = row.count + (amount or 1)
  row.arenas[arena] = true
end
local function arenaList(set)
  local values = {}
  for arena in pairs(set or {}) do values[#values + 1] = arena end
  table.sort(values)
  local ranges, first, last = {}, nil, nil
  for _, value in ipairs(values) do
    if first == nil then first, last = value, value
    elseif value == last + 1 then last = value
    else
      ranges[#ranges + 1] = first == last and ("%02d"):format(first)
        or ("%02d-%02d"):format(first, last)
      first, last = value, value
    end
  end
  if first ~= nil then
    ranges[#ranges + 1] = first == last and ("%02d"):format(first)
      or ("%02d-%02d"):format(first, last)
  end
  return table.concat(ranges, ",")
end

local totals = {
  primitives = 0, textures = 0, callbackTextures = 0, phase5 = 0,
  phase5Controllers = 0, phase5SecondTextures = 0, stageTransforms = 0,
  prelit = 0, normals = 0, cull = 0, texgen = 0, texgenLinear = 0,
  fogGeometry = 0, zbuffer = 0, materials = 0,
}
local gaps, features, muxes, renderModes, cycleTypes, commands = {}, {}, {}, {}, {}, {}
local controllerKinds, controllerModes, controllerPeriods = {}, {}, {}
local controllerSites = {}
local layoutCommands, layoutVariants = {}, {}
local rows = {}

-- Inventory the geo-layout language independently of extraction. Commands
-- which are structurally traversed but whose state semantics are not decoded
-- must not disappear from the parity report merely because they produce no
-- warning while walking the tree.
local function inspectLayout(data, root, arena)
  local seen, steps = {}, 0
  local function walk(offset, depth)
    if depth > 32 then return end
    while type(offset) == "number" and offset >= 0 and offset < #data do
      steps = steps + 1
      if steps > 100000 then return end
      local command = byte(data, offset)
      local size = command and Fragment.CMD_SIZES[command]
      if not size or offset + size > #data then return end
      local visit = ("%X:%d"):format(offset, depth)
      if seen[visit] then return end
      seen[visit] = true
      layoutCommands[command] = (layoutCommands[command] or 0) + 1
      if command == 0x09 or command == 0x0F or command == 0x25 then
        local variant = ("0x%02X:%02X%02X%02X"):format(command,
          byte(data, offset + 1) or 0, byte(data, offset + 2) or 0,
          byte(data, offset + 3) or 0)
        layoutVariants[variant] = (layoutVariants[variant] or 0) + 1
        if command == 0x09 then
          add(features, "geo-layout base graph node decoded", arena)
        elseif command == 0x0F then
          add(features, "ROM root render-state profile decoded", arena)
        else
          add(features, "ROM post-submission RDP reset decoded", arena)
        end
      end
      if command == 0x01 or command == 0x04 then
        return
      elseif command == 0x00 or command == 0x03 then
        local target = inside(data, u32(data, offset + 4), 1)
        if target then walk(target, depth + 1) end
      elseif command == 0x02 then
        offset = inside(data, u32(data, offset + 4), 1)
        if not offset then return end
        command = nil
      end
      if command ~= nil then offset = offset + size end
    end
  end
  walk(root, 0)
end

for _, record in ipairs(archive.records) do
  local arena = record.index
  local data = assert(Rom.decompress(assert(Rom.recordBytes(rom, record))))
  inspectLayout(data, assert(Fragment.stageRoot(data,
    ("arena_%02d"):format(arena))), arena)
  local model = assert(Fragment.extractStage(data, ("arena_%02d"):format(arena), arena))
  model.handlers = Handlers.readExtension(Handlers.packExtension(
    Handlers.compile(model.fx, data, BASE), BASE, data,
    { prims = model.prims, handlerTextures = model.handlerTextures }))
  Materials.attach(model)

  local state = select(1, Handlers.runExtension(model.handlers, 5,
    { geometryIndex = 0 }, {}))
  local alpha = { opaque = 0, cutout = 0, blend = 0 }
  local dynamic, secondTextures, fog, specialCombiner, normals, texgen, cull =
    0, 0, 0, 0, 0, 0, 0

  totals.primitives = totals.primitives + #model.prims
  totals.textures = totals.textures + #model.textures
  totals.callbackTextures = totals.callbackTextures + #model.handlerTextures
  totals.stageTransforms = totals.stageTransforms + #model.bones

  for _, node in ipairs(model.fx) do
    if node.handler == 0x81000148 and node.arg then
      totals.phase5 = totals.phase5 + 1
      local item = inside(data, u32(data, node.arg), 20)
      local controller = item and u32(data, item + 4) or 0
      if controller ~= 0 then
        dynamic = dynamic + 1
        totals.phase5Controllers = totals.phase5Controllers + 1
        add(features, "evaluated phase-5 material controller", arena)
        local spec = Phase5.controllerSpec(data, BASE, node.arg)
        local first = spec and spec.colorController
        local track = first and first.colorTrack
        if first then
          controllerModes[first.mode] = (controllerModes[first.mode] or 0) + 1
          controllerPeriods[first.period] = (controllerPeriods[first.period] or 0) + 1
        end
        if track then controllerKinds[track.kind] = (controllerKinds[track.kind] or 0) + 1 end
        controllerSites[#controllerSites + 1] = {
          arena = arena, site = node.commandOffset, kind = track and track.kind or -1,
          frames = track and track.frames or 0, keys = track and track.keys or 0,
          period = first and first.period or 0, mode = first and first.mode or -1,
          offset = first and first.offset or -1,
        }
      end
      local specs = Phase5.textureSpecs(data, BASE, node.arg)
      local textureUnits = {}
      for _, spec in ipairs(specs) do textureUnits[spec.phase5Texture or 0] = true end
      if textureUnits[0] and textureUnits[1] then
        secondTextures = secondTextures + 1
        totals.phase5SecondTextures = totals.phase5SecondTextures + 1
      end
      local material = Phase5.materialSpec(data, BASE, node.arg, 2)
      local combiner = material and material.combiner
      if combiner then
        muxes[key(combiner.selectors)] = (muxes[key(combiner.selectors)] or 0) + 1
        local c0, c1 = combiner.color0, combiner.color1
        local a0, a1 = combiner.alpha0, combiner.alpha1
        local function specialColor(cycle)
          return cycle[1] ~= cycle[2]
            and (cycle[2] == 6 or cycle[3] == 6 or cycle[3] >= 13)
        end
        local function specialAlpha(cycle)
          return cycle[1] ~= cycle[2]
            and (cycle[3] == 0 or cycle[3] == 6)
        end
        local usesLod = specialColor(c0) or specialColor(c1)
          or specialAlpha(a0) or specialAlpha(a1)
        if usesLod then
          specialCombiner = specialCombiner + 1
          add(features, "primitive-LOD combiner input implemented", arena)
        end
      else
        add(gaps, "phase-5 site has no decoded combiner", arena)
      end
    end
  end

  for _, prim in ipairs(model.prims) do
    alpha[prim.alphaMode or "opaque"] = (alpha[prim.alphaMode or "opaque"] or 0) + 1
    if prim.vertexSemantics == "normal" then
      totals.normals = totals.normals + 1
      normals = normals + 1
    else
      totals.prelit = totals.prelit + 1
    end
    local geometry = tonumber(prim.geometryMode) or 0
    if bits(geometry, 10, 1) ~= 0 then totals.cull = totals.cull + 1; cull = cull + 1 end
    if bits(geometry, 18, 1) ~= 0 then totals.texgen = totals.texgen + 1; texgen = texgen + 1 end
    if bits(geometry, 19, 1) ~= 0 then totals.texgenLinear = totals.texgenLinear + 1 end
    if bits(geometry, 16, 1) ~= 0 then
      fog = fog + 1
      totals.fogGeometry = totals.fogGeometry + 1
      add(gaps, "G_FOG geometry is extracted but no arena fog pass exists", arena)
    end
    if bits(geometry, 0, 1) ~= 0 then totals.zbuffer = totals.zbuffer + 1 end
    if bits(geometry, 10, 1) ~= 0 then
      add(features, "arena source culling retained with two-sided viewer policy", arena)
    end
    if bits(geometry, 19, 1) ~= 0 then
      add(gaps, "G_TEXTURE_GEN_LINEAR is reduced to ordinary texture generation", arena)
    end

    local material = prim.material
    if material then
      totals.materials = totals.materials + 1
      cycleTypes[material.cycleType or -1] = (cycleTypes[material.cycleType or -1] or 0) + 1
      renderModes[material.otherModeLow or 0] = (renderModes[material.otherModeLow or 0] or 0) + 1
      for _, command in ipairs(material.commands or {}) do
        commands[command.op] = (commands[command.op] or 0) + 1
      end
      if material.cycleType == 2 then
        add(gaps, "COPY-cycle material is rendered through the normal shader", arena)
      elseif material.cycleType == 3 then
        add(gaps, "FILL-cycle material is rendered through the normal shader", arena)
      end
      if material.fogColor and material.fogColor[4] ~= 0 then
        add(gaps, "authored fog colour is parsed but ignored", arena)
      end
      if material.blendColor and material.blendColor[4] ~= 0 then
        add(gaps, "authored blend/alpha-compare colour is parsed but ignored", arena)
      end
      if bits(material.otherModeLow or 0, 0, 2) ~= 0 then
        add(gaps, "alpha compare/dither state is not reproduced", arena)
      end
      -- RDP render mode occupies the upper 29 bits of other-mode low. LOVE's
      -- renderer currently classifies only opaque/cutout/blend/additive.
      if (material.otherModeLow or 0) ~= 0 then
        add(features, "non-default RDP render mode", arena)
      end
      local high = material.otherModeHigh or 0
      if bits(high, 16, 2) ~= 0 then
        add(gaps, "texture LOD/detail mode is parsed but ignored", arena)
      end
      if bits(high, 12, 2) ~= 0 then
        add(gaps, "texture conversion/filter state is approximated", arena)
      end
    end
  end

  -- The local stage display lists contain ordinary one-cycle texture loads;
  -- the parent renderer owns framebuffer state. The modern backend reduces
  -- that state to explicit queues and deterministic coplanar ordering rather
  -- than reproducing N64 depth precision artifacts.
  add(features, "explicit modern arena blend/depth/layer policy", arena,
    #model.prims)

  rows[#rows + 1] = {
    arena = arena, prims = #model.prims, textures = #model.textures,
    callbackTextures = #model.handlerTextures, dynamic = dynamic,
    secondTextures = secondTextures, fog = fog,
    specialCombiner = specialCombiner,
    normals = normals, texgen = texgen, cull = cull,
    alpha = alpha,
  }
end

print("arena\tprims\ttextures\tcallback_textures\tdynamic_phase5\tdual_texture\tnormals\ttexgen\tcull\tfog\tspecial_mux\talpha_o/c/b")
for _, row in ipairs(rows) do
  print(("%02d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d/%d/%d"):format(
    row.arena, row.prims, row.textures, row.callbackTextures, row.dynamic,
    row.secondTextures, row.normals, row.texgen, row.cull, row.fog,
    row.specialCombiner,
    row.alpha.opaque or 0, row.alpha.cutout or 0, row.alpha.blend or 0))
end
print(("TOTAL primitives=%d textures=%d callbackTextures=%d phase5=%d controllers=%d dualTexture=%d transforms=%d prelit=%d normals=%d cull=%d texgen=%d texgenLinear=%d fog=%d zbuffer=%d materials=%d uniqueMux=%d uniqueRenderMode=%d")
  :format(totals.primitives, totals.textures, totals.callbackTextures,
    totals.phase5, totals.phase5Controllers, totals.phase5SecondTextures,
    totals.stageTransforms, totals.prelit, totals.normals, totals.cull,
    totals.texgen, totals.texgenLinear, totals.fogGeometry, totals.zbuffer,
    totals.materials, (function() local n=0 for _ in pairs(muxes) do n=n+1 end return n end)(),
    (function() local n=0 for _ in pairs(renderModes) do n=n+1 end return n end)()))

print("GAPS")
local names = {}
for name in pairs(gaps) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local row = gaps[name]
  print(("%d\tarenas=%s\t%s"):format(row.count, arenaList(row.arenas), name))
end

print("MATERIAL_COMMANDS")
local ops = {}
for op in pairs(commands) do ops[#ops + 1] = op end
table.sort(ops)
for _, op in ipairs(ops) do print(("0x%02X\t%d"):format(op, commands[op])) end

print("CYCLE_TYPES")
local cycles = {}
for cycle in pairs(cycleTypes) do cycles[#cycles + 1] = cycle end
table.sort(cycles)
for _, cycle in ipairs(cycles) do print(("%d\t%d"):format(cycle, cycleTypes[cycle])) end

print("PHASE5_CONTROLLER_KINDS")
for kind, count in pairs(controllerKinds) do print(("%d\t%d"):format(kind, count)) end
print("PHASE5_CONTROLLER_MODES")
for mode, count in pairs(controllerModes) do print(("%d\t%d"):format(mode, count)) end
print("PHASE5_CONTROLLER_PERIODS")
for period, count in pairs(controllerPeriods) do print(("%d\t%d"):format(period, count)) end
print("PHASE5_CONTROLLER_SITES")
for _, row in ipairs(controllerSites) do
  print(("arena=%02d site=0x%X kind=%d frames=%d keys=%d period=%d mode=%d controller=0x%X")
    :format(row.arena, row.site, row.kind, row.frames, row.keys,
      row.period, row.mode, row.offset))
end

print("GEO_LAYOUT_COMMANDS")
local layoutOps = {}
for op in pairs(layoutCommands) do layoutOps[#layoutOps + 1] = op end
table.sort(layoutOps)
for _, op in ipairs(layoutOps) do
  print(("0x%02X\t%d"):format(op, layoutCommands[op]))
end
print("GEO_LAYOUT_STATE_VARIANTS")
local variants = {}
for variant in pairs(layoutVariants) do variants[#variants + 1] = variant end
table.sort(variants)
for _, variant in ipairs(variants) do
  print(("%s\t%d"):format(variant, layoutVariants[variant]))
end
