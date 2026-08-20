local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local ModelApi = {}
local Instance = {}
Instance.__index = Instance

local unpack = table.unpack or unpack

local function copyTable(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copyTable(item) end
  return out
end

local function copyOptions(options, excluded)
  local out = {}
  for key, value in pairs(type(options) == "table" and options or {}) do
    if not (excluded and excluded[key]) then out[key] = value end
  end
  return out
end

local function translation(x, y, z)
  return {
    1, 0, 0, tonumber(x) or 0,
    0, 1, 0, tonumber(y) or 0,
    0, 0, 1, tonumber(z) or 0,
    0, 0, 0, 1,
  }
end

local function scale(x, y, z)
  x = tonumber(x) or 1
  y = tonumber(y) or x
  z = tonumber(z) or x
  return {
    x, 0, 0, 0,
    0, y, 0, 0,
    0, 0, z, 0,
    0, 0, 0, 1,
  }
end

local function rotationX(angle)
  local c, s = math.cos(tonumber(angle) or 0), math.sin(tonumber(angle) or 0)
  return {1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1}
end

local function rotationY(angle)
  local c, s = math.cos(tonumber(angle) or 0), math.sin(tonumber(angle) or 0)
  return {c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1}
end

local function rotationZ(angle)
  local c, s = math.cos(tonumber(angle) or 0), math.sin(tonumber(angle) or 0)
  return {c,-s,0,0, s,c,0,0, 0,0,1,0, 0,0,0,1}
end

local function compose(...)
  local result = Renderer.identity()
  local values = {...}
  if #values == 1 and type(values[1]) == "table"
      and type(values[1][1]) == "table" then values = values[1] end
  for _, matrix in ipairs(values) do
    assert(type(matrix) == "table" and #matrix == 16, "compose expects 4x4 matrices")
    result = Renderer.matMul(result, matrix)
  end
  return result
end

-- Inverse transpose of the model matrix's upper-left 3x3. This supports
-- arbitrary caller transforms, including non-uniform scale.
local function normalFromModel(matrix)
  if type(matrix) ~= "table" or #matrix ~= 16 then
    return {1,0,0, 0,1,0, 0,0,1}
  end
  local a,b,c = matrix[1],matrix[2],matrix[3]
  local d,e,f = matrix[5],matrix[6],matrix[7]
  local g,h,i = matrix[9],matrix[10],matrix[11]
  local A,B,C = e*i-f*h, c*h-b*i, b*f-c*e
  local D,E,F = f*g-d*i, a*i-c*g, c*d-a*f
  local G,H,I = d*h-e*g, b*g-a*h, a*e-b*d
  local determinant = a*A+b*D+c*G
  if math.abs(determinant) < 1e-12 then return {1,0,0, 0,1,0, 0,0,1} end
  local n = 1/determinant
  -- Cofactor matrix is transpose(inverse(matrix)).
  return {A*n,D*n,G*n, B*n,E*n,H*n, C*n,F*n,I*n}
end

local function transform(options)
  options = type(options) == "table" and options or {}
  local position = options.position or options.translation or {}
  local rotation = options.rotation or {}
  local size = options.scale
  local sx, sy, sz
  if type(size) == "table" then sx,sy,sz = size[1] or size.x,size[2] or size.y,size[3] or size.z
  else sx,sy,sz = size,size,size end
  return compose(
    translation(position[1] or position.x, position[2] or position.y,
      position[3] or position.z),
    rotationZ(rotation[3] or rotation.z),
    rotationY(rotation[2] or rotation.y or options.yaw),
    rotationX(rotation[1] or rotation.x or options.pitch),
    scale(sx, sy, sz))
end

local Matrix = {
  convention = "row-major matrices multiplied by column vectors",
  identity = Renderer.identity,
  multiply = Renderer.matMul,
  perspective = Renderer.perspective,
  lookAt = Renderer.lookAt,
  orthographic = Renderer.ortho,
  translation = translation,
  scale = scale,
  rotationX = rotationX,
  rotationY = rotationY,
  rotationZ = rotationZ,
  compose = compose,
  transform = transform,
  normalFromModel = normalFromModel,
  stadiumModel = Renderer.modelMatrix,
  stadiumNormal = Renderer.normalMatrix,
}

local function graphicsScope(callback)
  local graphics = love and love.graphics
  local pushed = false
  if graphics and graphics.push and graphics.pop then
    pushed = pcall(graphics.push, "all")
  end
  local result = {pcall(callback)}
  if pushed then pcall(graphics.pop) end
  if not result[1] then return false, tostring(result[2]) end
  return unpack(result, 2)
end

local function live(instance)
  if getmetatable(instance) ~= Instance then return false, "invalid model instance" end
  if instance._released then return false, "model instance has been released" end
  return true
end

function Instance:model()
  local ok, err = live(self)
  if not ok then return nil, err end
  return self._model
end

function Instance:renderer()
  local ok, err = live(self)
  if not ok then return nil, err end
  return self._renderer
end

function Instance:play(value, loop, auxIndex)
  local ok, err = live(self)
  if not ok then return false, err end
  if type(value) == "string" and self._renderer.setContext
      and self._renderer:setContext(value, loop) then return true end
  return self._renderer:setAnimation(value, loop, auxIndex)
end

function Instance:playContext(name, loop)
  local ok, err = live(self)
  if not ok then return false, err end
  return self._renderer:setContext(name, loop)
end

function Instance:playAnimation(value, loop, auxIndex)
  local ok, err = live(self)
  if not ok then return false, err end
  return self._renderer:setAnimation(value, loop, auxIndex)
end

function Instance:playMove(move, loop)
  local ok, err = live(self)
  if not ok then return false, err end
  return self._renderer:setMove(move, loop)
end

function Instance:seekFrame(frame)
  local ok, err = live(self)
  if not ok then return false, err end
  if not self._renderer.seekFrame then return false, "frame seeking unavailable" end
  return self._renderer:seekFrame(frame)
end

function Instance:update(dt, runtime)
  local ok, err = live(self)
  if not ok then return false, err end
  if runtime and self._renderer.setHandlerRuntime then
    self._renderer:setHandlerRuntime(runtime, true)
  end
  return self._renderer:step(dt)
end

function Instance:animationState()
  local ok, err = live(self)
  if not ok then return nil, err end
  local renderer = self._renderer
  return {
    index = renderer.animIndex,
    frame = renderer.frame,
    time = renderer.time,
    loop = renderer.loop,
    finished = renderer.finished == true,
  }
end

function Instance:isFinished()
  local ok, err = live(self)
  if not ok then return nil, err end
  return self._renderer.finished == true
end

function Instance:metrics()
  local ok, err = live(self)
  if not ok then return nil, err end
  return copyTable(self._renderer:worldMetrics())
end

function Instance:bounds()
  local ok, err = live(self)
  if not ok then return nil, err end
  return copyTable(self._renderer:poseBounds())
end

function Instance:geometryAnchor()
  local ok, err = live(self)
  if not ok then return nil, err end
  return copyTable(self._renderer:geometryAnchor())
end

local function sceneOptions(options, modelMatrix)
  local camera = type(options.camera) == "table" and options.camera or {}
  local light = type(options.light) == "table" and options.light or {}
  local shadow = type(options.shadow) == "table" and options.shadow or {}
  local viewProjection = options.viewProjection or camera.viewProjection or camera.vp
  if type(viewProjection) ~= "table" then return nil, "viewProjection matrix required" end
  return {
    viewProjection = viewProjection,
    viewMatrix = options.viewMatrix or camera.view or Matrix.identity(),
    normalMatrix = options.normalMatrix or Matrix.normalFromModel(modelMatrix),
    lightDir = options.lightDir or light.direction,
    ambient = options.ambient or light.ambient,
    diffuse = options.diffuse or light.diffuse,
    tint = options.tint,
    flashAmount = options.flashAmount,
    flipWinding = options.flipWinding,
    disableCulling = options.disableCulling,
    skipHandlers = options.skipHandlers,
    sunMap = options.sunMap or shadow.map,
    sunVP = options.sunVP or shadow.viewProjection or shadow.vp,
    sunDark = options.sunDark or shadow.darkness,
    sunBias = options.sunBias or shadow.bias,
    sunTexel = options.sunTexel or shadow.texel,
  }
end

-- Draw into the caller's currently-bound color/depth target.
function Instance:draw(options)
  local ok, err = live(self)
  if not ok then return false, err end
  options = type(options) == "table" and options or {}
  local modelMatrix = options.modelMatrix or Matrix.identity()
  if type(modelMatrix) ~= "table" or #modelMatrix ~= 16 then
    return false, "modelMatrix must be a 4x4 matrix"
  end
  local drawOptions, optionErr = sceneOptions(options, modelMatrix)
  if not drawOptions then return false, optionErr end
  local pass = options.pass or "all"
  if pass ~= "all" and pass ~= "opaque" and pass ~= "additive" then
    return false, "pass must be all, opaque, or additive"
  end
  return graphicsScope(function()
    if pass == "all" then
      local drawn, drawErr = self._renderer:drawScene("opaque", modelMatrix, drawOptions)
      if not drawn then return false, drawErr end
      return self._renderer:drawScene("additive", modelMatrix, drawOptions)
    end
    return self._renderer:drawScene(pass, modelMatrix, drawOptions)
  end)
end

function Instance:drawShadow(options)
  local ok, err = live(self)
  if not ok then return false, err end
  options = type(options) == "table" and options or {}
  local modelMatrix = options.modelMatrix or Matrix.identity()
  local shadow = type(options.shadow) == "table" and options.shadow or {}
  local lightVP = options.lightViewProjection or options.lightVP
    or shadow.viewProjection or shadow.vp
  if type(modelMatrix) ~= "table" or #modelMatrix ~= 16 then
    return false, "modelMatrix must be a 4x4 matrix"
  end
  if type(lightVP) ~= "table" then return false, "lightViewProjection matrix required" end
  return graphicsScope(function()
    return self._renderer:drawShadowMap(modelMatrix, lightVP)
  end)
end

function Instance:release()
  if self._released then return false, "model instance has already been released" end
  self._released = true
  if self._renderer and self._renderer.release then
    pcall(self._renderer.release, self._renderer)
  end
  if self._ownsModel then
    local released, err = self._importer.releaseModel(self._model)
    self._model, self._renderer = nil, nil
    return released, err
  end
  self._model, self._renderer = nil, nil
  return true
end

local function instanceFromModel(importer, model, options, ownsModel)
  if type(model) ~= "table" then return nil, "model table required" end
  local rendererOptions = copyOptions(options, {takeOwnership=true})
  local renderer, err = importer.newRendererFromModel(model, rendererOptions)
  if not renderer then return nil, err end
  return setmetatable({
    _importer = importer,
    _model = model,
    _renderer = renderer,
    _ownsModel = ownsModel == true,
    _released = false,
  }, Instance)
end

function ModelApi.new(importer)
  assert(type(importer) == "table", "importer dependency required")
  local api = {
    apiVersion = 2,
    matrix = Matrix,
    matrices = Matrix,
    Instance = Instance,
    load = importer.loadModel,
    create = importer.createModel,
    createSpecial = importer.createSpecialModel,
    release = importer.releaseModel,
    newRenderer = importer.newRenderer,
    newRendererFromModel = importer.newRendererFromModel,
    readPack = importer.readPack,
    parsePack = importer.parsePack,
  }

  function api.capabilities()
    return {
      apiVersion = 2,
      ownedModels = true,
      ownedInstances = true,
      mutableModels = true,
      sceneNeutralDraw = true,
      animation = {context=true, move=true, index=true, seek=true},
      metrics = {bounds=true, height=true, floor=true, radius=true, rootScale=true},
      passes = {"opaque", "additive"},
      shadows = {cast=true, receive=true},
      matrixConvention = Matrix.convention,
    }
  end

  function api.newInstance(species, variant, options)
    local model, err = importer.createModel(species, variant)
    if not model then return nil, err end
    local instance, rendererErr = instanceFromModel(importer, model, options, true)
    if not instance then importer.releaseModel(model) end
    return instance, rendererErr
  end

  function api.newSpecialInstance(name, options)
    local model, err = importer.createSpecialModel(name)
    if not model then return nil, err end
    local instance, rendererErr = instanceFromModel(importer, model, options, true)
    if not instance then importer.releaseModel(model) end
    return instance, rendererErr
  end

  function api.newInstanceFromModel(model, options)
    return instanceFromModel(importer, model, options,
      type(options) == "table" and options.takeOwnership == true)
  end

  return api
end

return ModelApi
