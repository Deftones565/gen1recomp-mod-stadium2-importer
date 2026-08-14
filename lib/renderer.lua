local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local DynamicObject = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object")
local EffectRenderer = require("mods.STADIUM2_IMPORTER.lib.effect_renderer")
local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")
local RenderContract = require("mods.STADIUM2_IMPORTER.lib.render_contract")
local DualTexture = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.dual_texture_material")

local Renderer = {}
Renderer.__index = Renderer

Renderer.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexNormal", "float", 3 },
  { "VertexColor", "float", 4 },
}

local SHADER = [[
#define STADIUM_FLOAT LOVE_HIGHP_OR_MEDIUMP
varying STADIUM_FLOAT vec3 vNormal;
varying STADIUM_FLOAT vec3 vSun;
varying STADIUM_FLOAT vec2 vGeneratedUV;
varying STADIUM_FLOAT vec3 vEyeNormal;
#ifdef VERTEX
uniform mat4 mvp;
uniform mat4 modelMatrix;
uniform mat4 viewMatrix;
uniform mat4 sunVP;
uniform mat3 normalMatrix;
uniform vec2 textureGenScale;
uniform float billboardEnabled;
uniform vec3 billboardCenter;
uniform vec3 billboardRight;
uniform vec3 billboardUp;
uniform vec2 billboardSize;
uniform float decalDepthBias;
attribute vec3 VertexNormal;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  if (billboardEnabled > 0.5) {
    vertex_position.xyz = billboardCenter
      + billboardRight * ((VertexTexCoord.x - 0.5) * billboardSize.x)
      + billboardUp * ((1.0 - VertexTexCoord.y * 0.5) * billboardSize.y);
  }
  vNormal = normalize(normalMatrix * VertexNormal);
  vEyeNormal=normalize((viewMatrix*vec4(vNormal,0.0)).xyz);
  vGeneratedUV=(vEyeNormal.xy*0.5+vec2(0.5))*textureGenScale;
  vSun = (sunVP * (modelMatrix * vertex_position)).xyz;
  vec4 clip=mvp*vertex_position;
  // Coplanar eye/marking layers can alternate with their body primitive in
  // a 16-bit mobile depth buffer. Move only authored decals a few depth units
  // toward the camera; ordinary geometry keeps strict depth testing.
  clip.z-=decalDepthBias*clip.w;
  return clip;
}
#endif
#ifdef PIXEL
uniform Image MainTex;
uniform vec3 lightDir;
uniform vec3 ambient;
uniform vec3 diffuse;
uniform vec4 primitiveColor;
uniform vec4 environmentColor;
uniform float environmentMix;
uniform Image secondaryTexture;
uniform float secondaryEnabled;
uniform float secondaryMix;
uniform vec4 textureScroll;
uniform float alphaCutoff;
uniform vec2 primarySize;
uniform vec2 secondarySize;
uniform vec4 sceneTint;
uniform float flashAmount;
uniform Image sunMap;
uniform float sunEnabled;
uniform float sunDark;
uniform float sunBias;
uniform vec2 sunTexel;
uniform float effectIntensityMode;
uniform float lightingEnabled;
uniform float celShadingEnabled;
uniform float textureGenEnabled;
uniform vec2 textureCoordinateScale;
uniform vec2 primaryWrapMode;
uniform vec2 secondaryWrapMode;
uniform float boundedUVEnabled;
float shadowDepth(vec2 uv) {
  vec4 c=Texel(sunMap,uv);
  return c.r+c.g*(1.0/255.0);
}
float sunlight(vec3 p) {
  if (sunEnabled<0.5 || p.x<0.0 || p.x>1.0 || p.y<0.0 || p.y>1.0 || p.z>1.0) return 1.0;
  float z=p.z-sunBias;
#ifdef GL_ES
  // Packed 8-bit shadow depth plus mediump interpolation makes four binary
  // PCF comparisons disagree within a primitive on mobile. One filtered,
  // softly-thresholded comparison keeps the same shadow strength without the
  // speckled surface noise.
  float mapDepth=shadowDepth(p.xy);
  float edge=max(sunBias,1.0/255.0);
  float lit=smoothstep(mapDepth-edge,mapDepth+edge,z);
  return 1.0-sunDark*lit;
#else
  // Four taps, as before, but distributed as a rotated 3x3 footprint. This
  // widens the penumbra and avoids square stair-steps without another fetch.
  float lit=step(z,shadowDepth(p.xy+sunTexel*vec2(-1.5,-0.5)))
    +step(z,shadowDepth(p.xy+sunTexel*vec2(0.5,-1.5)))
    +step(z,shadowDepth(p.xy+sunTexel*vec2(1.5,0.5)))
    +step(z,shadowDepth(p.xy+sunTexel*vec2(-0.5,1.5)));
  return 1.0-sunDark*(1.0-lit*0.25);
#endif
}
float foldTextureCoordinate(float value, float mode) {
  if (mode < 0.5) return clamp(value, 0.0, 1.0);
  if (mode < 1.5) return mod(value, 1.0);
  float mirrored = mod(value, 2.0);
  return mirrored <= 1.0 ? mirrored : 2.0 - mirrored;
}
STADIUM_FLOAT vec2 foldTextureUV(STADIUM_FLOAT vec2 uv, vec2 mode) {
  return vec2(foldTextureCoordinate(uv.x, mode.x),
    foldTextureCoordinate(uv.y, mode.y));
}
vec4 sample3(Image image, STADIUM_FLOAT vec2 uv, vec2 size, vec2 wrapMode) {
  // Keep the 3-point filter's floor/fract work inside one texture tile.
  // Mobile fragment shaders can use mediump arithmetic, where multiplying a
  // large repeated/scrolled UV by the texture size destroys the fractional
  // texel position and produces primitive-local crawling/noise.
  if (boundedUVEnabled > 0.5) uv = foldTextureUV(uv, wrapMode);
  STADIUM_FLOAT vec2 p = uv * size - vec2(0.5);
  STADIUM_FLOAT vec2 base = floor(p);
  STADIUM_FLOAT vec2 f = fract(p);
  STADIUM_FLOAT vec2 texel = vec2(1.0) / size;
  if (f.x + f.y < 1.0) {
    vec2 o = (base + vec2(0.5)) * texel;
    return Texel(image, o) * (1.0-f.x-f.y)
      + Texel(image, o + vec2(texel.x,0.0)) * f.x
      + Texel(image, o + vec2(0.0,texel.y)) * f.y;
  }
  vec2 o = (base + vec2(1.5)) * texel;
  return Texel(image, o) * (f.x+f.y-1.0)
    + Texel(image, o - vec2(texel.x,0.0)) * (1.0-f.y)
    + Texel(image, o - vec2(0.0,texel.y)) * (1.0-f.x);
}
void effect() {
  vec4 color=VaryingColor;
  STADIUM_FLOAT vec2 texture_coords=VaryingTexCoord.st;
  STADIUM_FLOAT vec2 screen_coords=love_PixelCoord;
  STADIUM_FLOAT vec2 uv=mix(texture_coords*textureCoordinateScale,
    vGeneratedUV,textureGenEnabled);
  vec4 texel = sample3(MainTex, uv + textureScroll.xy, primarySize, primaryWrapMode);
  if (secondaryEnabled > 0.5) {
    vec4 other = sample3(secondaryTexture, uv + textureScroll.zw, secondarySize,
      secondaryWrapMode);
    texel = mix(texel, other, secondaryMix);
  }
  if (effectIntensityMode > 0.5) {
    float intensity = texel.r;
    float gasAlpha = intensity * primitiveColor.a * color.a * sceneTint.a;
    if (gasAlpha <= alphaCutoff) discard;
    vec3 gasColor = mix(environmentColor.rgb, primitiveColor.rgb, intensity);
    love_PixelColor=vec4(gasColor * color.rgb * sceneTint.rgb, gasAlpha);
    return;
  }
  texel *= color * primitiveColor;
  if (texel.a <= alphaCutoff) discard;
  vec3 n=normalize(vNormal);
  float stadiumShade=clamp(0.7725+n.x*0.06+n.y*0.225+n.z*0.11,0.30,1.0);
  vec3 lit=vec3(stadiumShade);
  vec3 combined = mix(texel.rgb, texel.rgb * environmentColor.rgb, environmentMix);
  // Stadium's shade includes an ambient component. Shadow only the direct
  // portion so self-shadowing cannot crush already-dark faces toward black.
  float shadowVisibility=sunlight(vSun);
  float litShade=0.30+(stadiumShade-0.30)*shadowVisibility;
  float mangaAmount=celShadingEnabled*lightingEnabled;
  float washShade=floor(litShade*3.0+0.5)/3.0;
  litShade=mix(litShade,washShade,mangaAmount);
  vec3 lighting=mix(vec3(1.0),vec3(litShade),lightingEnabled);
  vec3 shaded=combined * lighting * sceneTint.rgb;
  if (mangaAmount > 0.001) {
    // Watercolor-manga mode stays in the existing material pass. A warm paper
    // lift, muted pigment and screen-stable irregularity suggest a physical
    // wash; the grazing-angle term lays ink inside the silhouette without a
    // second expanded-mesh outline draw.
    STADIUM_FLOAT float paperNoise=fract(sin(dot(floor(screen_coords.xy*0.5),
      vec2(12.9898,78.233)))*43758.5453)-0.5;
    STADIUM_FLOAT float broadWash=
      sin(screen_coords.x*0.021+screen_coords.y*0.017)*0.5
      +sin(screen_coords.x*0.009-screen_coords.y*0.013)*0.5;
    float pigmentVariation=1.0+paperNoise*0.075+broadWash*0.025;
    float pigmentGray=dot(shaded,vec3(0.299,0.587,0.114));
    vec3 watercolor=mix(vec3(pigmentGray),shaded,0.82)*pigmentVariation;
    watercolor=mix(vec3(1.0,0.965,0.885),watercolor,0.94);
    float ink=1.0-smoothstep(0.025,0.15,abs(vEyeNormal.z));
    float hatch=smoothstep(0.58,0.76,
      fract((screen_coords.x+screen_coords.y)*0.115+paperNoise*0.35));
    float inkMark=ink*(0.22+0.78*hatch);
    watercolor*=mix(1.0,0.18,inkMark);
    shaded=mix(shaded,watercolor,mangaAmount);
  }
  shaded=mix(shaded,vec3(1.0),flashAmount);
  love_PixelColor=vec4(shaded,
    texel.a * mix(1.0, environmentColor.a, environmentMix) * sceneTint.a);
}
#endif
]]

local SHADOW_SHADER = [[
varying float vDepth;
#ifdef VERTEX
uniform mat4 lightVP;
uniform mat4 modelMatrix;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
  vec4 c=lightVP*(modelMatrix*vertex_position);
  vDepth=c.z*0.5+0.5;
  return c;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc) {
  if (Texel(tex,tc).a<0.5) discard;
  float d=clamp(vDepth,0.0,1.0)*255.0;
  return vec4(floor(d)/255.0,fract(d),0.0,1.0);
}
#endif
]]

-- A deliberately small compatibility shader. Raw model coordinates must
-- never reach LOVE's default 2D transform: Stadium units are then interpreted
-- as screen pixels, putting the model at the canvas origin and making every
-- camera control appear broken. Drivers that reject the lit shader still get
-- the same projection and texture path through this one.
local CAMERA_SHADER = [[
#ifdef VERTEX
uniform mat4 mvp;
uniform float billboardEnabled;
uniform vec3 billboardCenter;
uniform vec3 billboardRight;
uniform vec3 billboardUp;
uniform vec2 billboardSize;
uniform float decalDepthBias;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  if (billboardEnabled > 0.5) {
    vertex_position.xyz = billboardCenter
      + billboardRight * ((VertexTexCoord.x - 0.5) * billboardSize.x)
      + billboardUp * ((1.0 - VertexTexCoord.y * 0.5) * billboardSize.y);
  }
  vec4 clip=mvp*vertex_position;
  clip.z-=decalDepthBias*clip.w;
  return clip;
}
#endif
#ifdef PIXEL
uniform vec4 primitiveColor;
uniform vec4 environmentColor;
uniform float effectIntensityMode;
vec4 effect(vec4 color, Image image, vec2 texture_coords, vec2 screen_coords) {
  vec4 texel = Texel(image, texture_coords);
  if (effectIntensityMode > 0.5) {
    float intensity = texel.r;
    float alpha = intensity * primitiveColor.a * color.a;
    if (alpha <= 0.001) discard;
    return vec4(mix(environmentColor.rgb, primitiveColor.rgb, intensity) * color.rgb, alpha);
  }
  texel *= color;
  if (texel.a <= 0.001) discard;
  return texel;
}
#endif
]]

Renderer.SHADER_SOURCE = SHADER
Renderer.CAMERA_SHADER_SOURCE = CAMERA_SHADER

function Renderer.shaderSource(forceMediump)
  if not forceMediump then return SHADER end
  return (SHADER:gsub("#define STADIUM_FLOAT LOVE_HIGHP_OR_MEDIUMP",
    "#define STADIUM_FLOAT mediump", 1))
end

function Renderer.compileShaderAudit(forceMediump)
  if not (love and love.graphics and love.graphics.newShader) then
    return false, "LÖVE shader compiler unavailable"
  end
  local ok, shader = pcall(love.graphics.newShader,
    Renderer.shaderSource(forceMediump))
  if not ok or not shader then return false, tostring(shader) end
  if shader.release then pcall(shader.release, shader) end
  return true
end

local floor = math.floor
local unpack = table.unpack or unpack
local sin, cos, sqrt = math.sin, math.cos, math.sqrt
local pi = math.pi

local function identity()
  return {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  }
end

local function matMul(a, b)
  local o = {}
  for r = 0, 3 do
    for c = 0, 3 do
      local v = 0
      for k = 0, 3 do v = v + a[r * 4 + k + 1] * b[k * 4 + c + 1] end
      o[r * 4 + c + 1] = v
    end
  end
  return o
end

local function perspective(fovy, aspect, near, far, shiftX, shiftY)
  local f = 1 / math.tan(fovy * 0.5)
  shiftX, shiftY = tonumber(shiftX) or 0, tonumber(shiftY) or 0
  return {
    f / aspect, 0, -shiftX, 0,
    0, f, -shiftY, 0,
    0, 0, (far + near) / (near - far), (2 * far * near) / (near - far),
    0, 0, -1, 0,
  }
end

local function lookAt(ex, ey, ez, tx, ty, tz)
  local fx, fy, fz = tx - ex, ty - ey, tz - ez
  local fl = sqrt(fx * fx + fy * fy + fz * fz)
  if fl == 0 then fl = 1 end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local ux, uy, uz = 0, 1, 0
  local sx, sy, sz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
  local sl = sqrt(sx * sx + sy * sy + sz * sz)
  if sl == 0 then sx, sy, sz, sl = 1, 0, 0, 1 end
  sx, sy, sz = sx / sl, sy / sl, sz / sl
  ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
  return {
    sx, sy, sz, -(sx * ex + sy * ey + sz * ez),
    ux, uy, uz, -(ux * ex + uy * ey + uz * ez),
    -fx, -fy, -fz, fx * ex + fy * ey + fz * ez,
    0, 0, 0, 1,
  }
end

local function modelMatrix(yaw, pitch, scale, cx, cy, cz, flipY)
  local y = yaw or 0
  local p = pitch or 0
  local sy, cyaw = sin(y), cos(y)
  local sp, cp = sin(p), cos(p)
  local s = scale or 1
  local fy = flipY == false and 1 or -1
  local ry = {
    cyaw, 0, sy, 0,
    0, 1, 0, 0,
    -sy, 0, cyaw, 0,
    0, 0, 0, 1,
  }
  local rx = {
    1, 0, 0, 0,
    0, cp, -sp, 0,
    0, sp, cp, 0,
    0, 0, 0, 1,
  }
  local sc = {
    s, 0, 0, -cx * s,
    0, s * fy, 0, -cy * s * fy,
    0, 0, s, -cz * s,
    0, 0, 0, 1,
  }
  return matMul(ry, matMul(rx, sc))
end

local function normalMatrix(yaw, pitch, flipY)
  local y = yaw or 0
  local p = pitch or 0
  local sy, cyaw = sin(y), cos(y)
  local sp, cp = sin(p), cos(p)
  local fy = flipY == false and 1 or -1
  return {
    cyaw, sy * sp * fy, sy * cp,
    0, cp * fy, -sp,
    -sy, cyaw * sp * fy, cyaw * cp,
  }
end

local function normalize3(x, y, z)
  local n = sqrt(x * x + y * y + z * z)
  if n <= 0 then return 0, 1, 0 end
  return x / n, y / n, z / n
end

local function sampleComponent(c, frame, fallback)
  if c == nil then return fallback end
  if type(c) ~= "table" then return c end
  if #c == 0 then return fallback end
  local at = frame + 1
  if at < 1 then at = 1 end
  if at > #c then at = #c end
  return c[at]
end

local function samplePose(model, animIndex, frame)
  local anim = animIndex and model.anims and model.anims[animIndex] or nil
  return function(i)
    local bone = model.bones[i]
    if not anim then return bone.t, bone.r, bone.s end
    local tr = anim.tracks[i]
    if not tr then return bone.t, bone.r, bone.s end
    return {
      sampleComponent(tr.t[1], frame, bone.t[1]),
      sampleComponent(tr.t[2], frame, bone.t[2]),
      sampleComponent(tr.t[3], frame, bone.t[3]),
    }, {
      sampleComponent(tr.r[1], frame, bone.r[1]),
      sampleComponent(tr.r[2], frame, bone.r[2]),
      sampleComponent(tr.r[3], frame, bone.r[3]),
    }, {
      sampleComponent(tr.s[1], frame, bone.s[1]),
      sampleComponent(tr.s[2], frame, bone.s[2]),
      sampleComponent(tr.s[3], frame, bone.s[3]),
    }
  end
end

local function nextFrame(anim, frame, loop)
  if not anim or anim.frames <= 1 then return frame end
  if frame + 1 < anim.frames then return frame + 1 end
  if loop == false then return frame end
  return math.max(0, math.min(anim.frames - 1, anim.loopStart or 0))
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Stadium stores rotations as Euler triples in signed binary-angle units.
-- We render at 60 Hz while the source pose stream advances at 30 Hz, so the
-- renderer invents one halfway pose between source frames.  A naive Euler
-- lerp is unsafe: the game is free to re-express nearly the same orientation
-- with a very different triple, and interpolating those components makes a
-- limb flip inside-out for the invented half-frame.  The original game never
-- draws that in-between pose because it steps the 30 Hz stream directly.
local BREAK_ANGLE = 16384 -- pi/2 in one 30 Hz frame: treat as a snap/re-expression
local BREAK_MOVE = 0.5    -- half a model height in one frame: treat as a teleport

local function angleDelta(a, b)
  local d = b - a
  if d > 32768 then d = d - 65536
  elseif d < -32768 then d = d + 65536 end
  return d
end

local function samplePoseInterpolated(model, animIndex, frame, alpha, loop)
  local anim = animIndex and model.anims and model.anims[animIndex] or nil
  if not anim or alpha <= 0 then return samplePose(model, animIndex, frame) end
  local a = samplePose(model, animIndex, frame)
  local b = samplePose(model, animIndex, nextFrame(anim, frame, loop))

  local moveBreak
  local root = tonumber(model.rootScale) or 1
  if root == 0 then root = 1 end
  local rawHeight = (tonumber(model.height) or 0) / math.abs(root)
  if rawHeight > 0 then moveBreak = rawHeight * BREAK_MOVE end

  return function(i)
    local at, ar, as = a(i)
    local bt, br, bs = b(i)

    -- Translation is one vector.  If any axis teleports farther than half the
    -- Pokemon's raw height, hold the source frame instead of manufacturing a
    -- halfway position the cartridge never had.
    local tx, ty, tz = bt[1] - at[1], bt[2] - at[2], bt[3] - at[3]
    local moveBlend = alpha
    if moveBreak and (math.abs(tx) > moveBreak or math.abs(ty) > moveBreak
        or math.abs(tz) > moveBreak) then
      moveBlend = 0
    end

    -- Rotation is also one value conceptually: either all three Euler
    -- components blend, or none do.  Shortest-arc wrapping handles the +/-pi
    -- seam; the BREAK_ANGLE guard handles equivalent-Euler re-expression.
    local rx, ry, rz = angleDelta(ar[1], br[1]), angleDelta(ar[2], br[2]),
      angleDelta(ar[3], br[3])
    local rotBlend = alpha
    if math.abs(rx) > BREAK_ANGLE or math.abs(ry) > BREAK_ANGLE
        or math.abs(rz) > BREAK_ANGLE then
      rotBlend = 0
    end

    return {
      lerp(at[1], bt[1], moveBlend), lerp(at[2], bt[2], moveBlend),
      lerp(at[3], bt[3], moveBlend),
    }, {
      ar[1] + rx * rotBlend, ar[2] + ry * rotBlend, ar[3] + rz * rotBlend,
    }, {
      lerp(as[1], bs[1], alpha), lerp(as[2], bs[2], alpha),
      lerp(as[3], bs[3], alpha),
    }
  end
end

local function sourceFrame(anim, time, loop)
  if not anim or anim.frames <= 0 then return 0, true end
  local raw = floor(math.max(0, tonumber(time) or 0) * Pack.FPS)
  if raw < anim.frames then return raw, false end
  if loop == false then return anim.frames - 1, true end
  local start = math.max(0, math.min(anim.frames - 1, anim.loopStart or 0))
  local span = anim.frames - start
  if span <= 0 then return anim.frames - 1, false end
  return start + ((raw - start) % span), false
end

function Renderer.meshRows(prim)
  local rows = {}
  local us, vs = Sampler.uvScale(prim.sampler, prim.textureScale)
  local minU,maxU,minV,maxV=math.huge,-math.huge,math.huge,-math.huge
  for i=1,prim.nverts do
    local u,v=(prim.uv[i*2-1] or 0)*us,(prim.uv[i*2] or 0)*vs
    minU,maxU=math.min(minU,u),math.max(maxU,u)
    minV,maxV=math.min(minV,v),math.max(maxV,v)
  end
  local anchorU,anchorV=0,0
  -- Callback textures can have a different resolution and therefore a
  -- non-integral coordinate scale. Their phase cannot use the source
  -- texture's periodic origin safely.
  if not prim.callbackOffset then
    local wrapS,wrapT=Sampler.wrap(prim.sampler)
    anchorU=Sampler.coordinateAnchor(minU,maxU,wrapS)
    anchorV=Sampler.coordinateAnchor(minV,maxV,wrapT)
  end
  for i = 1, prim.nverts do
    local color = prim.vertexSemantics == "color" and prim.color or nil
    rows[i] = { 0, 0, 0, prim.uv[i * 2 - 1] * us-anchorU,
      prim.uv[i * 2] * vs-anchorV, 0, 1, 0,
      color and color[i * 4 - 3] / 255 or 1, color and color[i * 4 - 2] / 255 or 1,
      color and color[i * 4 - 1] / 255 or 1, color and color[i * 4] / 255 or 1 }
  end
  return rows,anchorU,anchorV
end

local function makeMesh(prim)
  local rows = Renderer.meshRows(prim)
  if not (love and love.graphics and love.graphics.newMesh) then return nil, rows end
  local ok, mesh = pcall(love.graphics.newMesh, Renderer.FORMAT, rows, "triangles", "dynamic")
  if not ok then return nil, rows end
  if mesh.setVertexMap then pcall(mesh.setVertexMap, mesh, prim.idx) end
  return mesh, rows
end

local function makeDynamicMesh()
  local rows = {
    {0,0,0,0,1,0,0,1,1,1,1,1},
    {0,0,0,1,1,0,0,1,1,1,1,1},
    {0,0,0,1,0,0,0,1,1,1,1,1},
    {0,0,0,0,0,0,0,1,1,1,1,1},
  }
  if not (love and love.graphics and love.graphics.newMesh) then return nil, rows end
  local ok, mesh = pcall(love.graphics.newMesh, Renderer.FORMAT, rows, "triangles", "dynamic")
  if not ok then return nil, rows end
  if mesh.setVertexMap then pcall(mesh.setVertexMap, mesh, {1,2,3,1,3,4}) end
  return mesh, rows
end

local function sendFlameBillboard(shader, part, view, model)
  if not (shader and shader.send) then return end
  if not (part and part.prim and part.prim.effect == "fire"
      and part.rows and #part.rows >= 10) then
    pcall(shader.send, shader, "billboardEnabled", 0)
    return
  end
  local tipA, tipB, baseA, baseB = part.rows[1], part.rows[2],
    part.rows[9], part.rows[10]
  local center = { (baseA[1] + baseB[1]) * .5,
    (baseA[2] + baseB[2]) * .5, (baseA[3] + baseB[3]) * .5 }
  local tip = { (tipA[1] + tipB[1]) * .5,
    (tipA[2] + tipB[2]) * .5, (tipA[3] + tipB[3]) * .5 }
  local width = math.sqrt((baseB[1]-baseA[1])^2
    + (baseB[2]-baseA[2])^2 + (baseB[3]-baseA[3])^2)
  local height = math.sqrt((tip[1]-center[1])^2
    + (tip[2]-center[2])^2 + (tip[3]-center[3])^2)
  local vm = matMul(view or identity(), model or identity())
  local rx, ry, rz = normalize3(vm[1], vm[2], vm[3])
  local ux, uy, uz = normalize3(vm[5], vm[6], vm[7])
  pcall(shader.send, shader, "billboardCenter", center)
  pcall(shader.send, shader, "billboardRight", {rx,ry,rz})
  pcall(shader.send, shader, "billboardUp", {ux,uy,uz})
  pcall(shader.send, shader, "billboardSize", {width,height})
  pcall(shader.send, shader, "billboardEnabled", 1)
end

local function makeCanvas(w, h, msaa)
  if not (love and love.graphics and love.graphics.newCanvas) then return nil end
  msaa = math.max(0, floor(tonumber(msaa) or 0))
  local okColor, color = pcall(love.graphics.newCanvas, w, h, { format = "rgba8", readable = true, dpiscale = 1, msaa = msaa })
  if not okColor then
    okColor, color = pcall(love.graphics.newCanvas, w, h)
  end
  if not okColor then return nil end
  local depth
  for _,format in ipairs({"depth24stencil8","depth24","depth16","depth32f"}) do
    local okDepth,d=pcall(love.graphics.newCanvas,w,h,
      {format=format,readable=false,dpiscale=1,msaa=msaa})
    if okDepth and d then depth=d break end
  end
  if color.setFilter then pcall(color.setFilter, color, "linear", "linear") end
  return color, depth, depth == nil
end

local function imageDimensions(image, fallback)
  if image and image.getDimensions then
    local ok,w,h=pcall(image.getDimensions,image)
    if ok and w and h then return w,h end
  end
  return (fallback and fallback.w) or 1,(fallback and fallback.h) or 1
end

local function resolvedTextureWrap(prim, material, set)
  local wrapS, wrapT = Sampler.wrap(prim and prim.sampler)
  if material then
    wrapS = material.wrapS or wrapS
    wrapT = material.wrapT or wrapT
  end
  if set and set.wrap then wrapS, wrapT = set.wrap, set.wrap end
  return wrapS, wrapT
end

local function sendTextureWrapMode(shader, uniform, wrapS, wrapT)
  if not (shader and shader.send) then return end
  pcall(shader.send, shader, uniform,
    {Sampler.wrapCode(wrapS), Sampler.wrapCode(wrapT)})
end

local function foldedTextureScroll(scroll, wrapS, wrapT, enabled)
  if not enabled then
    return scroll and scroll[1] or 0, scroll and scroll[2] or 0
  end
  return Sampler.foldOffset(scroll and scroll[1] or 0, wrapS),
    Sampler.foldOffset(scroll and scroll[2] or 0, wrapT)
end

function Renderer.shouldBoundTextureUV(options)
  if type(options) == "table" and options.boundedTextureUV ~= nil then
    return options.boundedTextureUV == true
  end
  if Renderer.isMobileGraphics() then return true end
  if love and love.graphics and love.graphics.getSupported then
    local ok,supported=pcall(love.graphics.getSupported)
    if ok and type(supported)=="table" and supported.pixelshaderhighp == false then
      return true
    end
  end
  return false
end

function Renderer.isMobileGraphics()
  if not (love and love.graphics and love.graphics.getRendererInfo) then return false end
  local ok,name,version,vendor,device=pcall(love.graphics.getRendererInfo)
  if not ok then return false end
  local label=table.concat({tostring(name or ""),tostring(version or ""),
    tostring(vendor or ""),tostring(device or "")}," "):lower()
  return label:find("opengl es",1,true)~=nil or label:find("gles",1,true)~=nil
    or label:find("metal",1,true)~=nil
end

function Renderer.shouldReceiveModelSunShadows(options)
  if type(options)=="table" and options.modelSunShadows~=nil then
    return options.modelSunShadows==true
  end
  -- Android/iOS keep the shared cast-shadow pass for the arena, but packed
  -- self-shadow depth is unstable across GLES tile renderers and obscures
  -- texture details with acne. Desktop retains the reference self-shadow.
  return not Renderer.isMobileGraphics()
end

function Renderer.new(model, options)
  if type(model) ~= "table" or not model.prims then return nil, "model required" end
  options = type(options) == "table" and options or {}
  local idleIndex = Pack.contextIndex(model, "idle") or (model.anims[1] and 1 or nil)
  local self = setmetatable({
    model = model,
    parts = {},
    time = 0,
    animIndex = nil,
    loop = true,
    frame = 0,
    finished = false,
    yaw = tonumber(options.yaw) or 0,
    pitch = tonumber(options.pitch) or 0,
    boundedTextureUV = Renderer.shouldBoundTextureUV(options),
    receiveModelSunShadows = Renderer.shouldReceiveModelSunShadows(options),
    decalDepthBias = math.max(0,tonumber(options.decalDepthBias) or (4/65535)),
    fov = tonumber(options.fov) or (35 * pi / 180),
    lightDir = options.lightDir or { 0.35, 0.7, 0.62 },
    ambient = options.ambient or { 0.46, 0.46, 0.46 },
    diffuse = options.diffuse or { 0.72, 0.72, 0.72 },
    flipY = options.flipY ~= false,
    textureFilter = options.textureFilter == "linear" and "linear" or "nearest",
    anisotropy = math.max(1, tonumber(options.anisotropy) or 4),
    shaderStyle = options.shaderStyle == "cel" and "cel" or "stadium",
    shaderStyleProvider = type(options.shaderStyleProvider) == "function"
      and options.shaderStyleProvider or nil,
    handlerRuntime = {},
    randomSeed = math.floor(tonumber(options.randomSeed) or 1),
    handlerState = {},
    deferred = {},
    dynamicMeshes = {},
    handlerBoneAnchors = {},
    anchorEnabled = options.anchorTravel == true,
  }, Renderer)
  for i, prim in ipairs(model.prims) do
    local mesh, rows = makeMesh(prim)
    local used = {}
    for _, vi in ipairs(prim.idx or {}) do used[vi] = true end
    self.parts[i] = { prim = prim, mesh = mesh, rows = rows, visible = {}, used = used }
  end
  if love and love.graphics and love.graphics.newShader then
    local forceMediump = options.forceMediumpShader == true
    local ok, shader = pcall(love.graphics.newShader,
      Renderer.shaderSource(forceMediump))
    if ok and shader then
      self.shader, self.shaderTier = shader, "lit"
    else
      self.shaderError = tostring(shader)
      local fallbackOK, fallback = pcall(love.graphics.newShader, CAMERA_SHADER)
      if fallbackOK and fallback then
        self.shader, self.shaderTier = fallback, "camera"
      else
        return nil, ("Stadium 2 model shader unavailable: %s; fallback: %s")
          :format(self.shaderError, tostring(fallback))
      end
    end
    local shadowOK,shadow=pcall(love.graphics.newShader,SHADOW_SHADER)
    if shadowOK then self.shadowShader=shadow end
  elseif love and love.graphics then
    return nil, "Stadium 2 model shader support is unavailable"
  end
  if model.handlers then
    self.handlerState, self.deferred = Handlers.runExtension(model.handlers, 0,
      { modelContext = self, node = self }, self.handlerState)
  end
  self:updatePose(true)
  self.bindAnchor=self:geometryAnchor()
  self.bindBounds = self:poseBounds()
  if not model.staticPose then self.animIndex = idleIndex end
  self:updatePose(true)
  return self
end

function Renderer:currentShaderStyle()
  if self.shaderStyleProvider then
    local ok, value = pcall(self.shaderStyleProvider)
    if ok then return value == "cel" and "cel" or "stadium" end
  end
  return self.shaderStyle == "cel" and "cel" or "stadium"
end

function Renderer:geometryAnchor()
  local x,y,z,n=0,0,0,0
  for _,part in ipairs(self.parts or {}) do
    for i,row in ipairs(part.rows or {}) do
      if part.used[i] and part.visible[i]~=false then
        x,y,z,n=x+row[1],y+row[2],z+row[3],n+1
      end
    end
  end
  if n==0 then return {0,0,0} end
  return {x/n,y/n,z/n}
end

function Renderer:setAnimation(value, loop, auxIndex)
  if self.model.staticPose then return false end
  local index
  if type(value) == "number" then
    index = floor(value)
  elseif type(value) == "string" then
    index = self.model.animByName[value] or Pack.contextIndex(self.model, value)
  end
  if not (index and self.model.anims[index]) then return false end
  self.animIndex = index
  self.loop = loop ~= false
  self.auxIndex = auxIndex
  self.time = 0
  self.frame = 0
  self.finished = false
  self:updatePose(true)
  return true
end

function Renderer:setMove(move, loop)
  local index = Pack.moveIndex(self.model, move)
  if not index then return false end
  local aux=self.model.moveAux and self.model.moveAux[move]
  if aux and aux>=0 then aux=aux+1 else aux=nil end
  return self:setAnimation(index, loop, aux)
end

function Renderer:setContext(name, loop)
  local index = Pack.contextIndex(self.model, name)
  if not index then return false end
  return self:setAnimation(index, loop)
end

function Renderer:setHandlerRuntime(runtime, defer)
  self.handlerRuntime = type(runtime) == "table" and runtime or {}
  if not defer then self:updateHandlers() end
end

function Renderer:handlerValues()
  local values = {
    species = self.model and self.model.species,
    sourceFrame = self.frame,
    frame = self.frame,
    textureFrame = self.frame,
    -- func_81005B50 reads a global display-frame counter, not the model's
    -- looping animation frame. Keep this material moving across anim loops.
    materialFrame = math.floor(self.time * 60),
    time = self.time,
    randomSeed = self.randomSeed,
    modelContext = self,
    node = self,
  }
  for key, value in pairs(self.handlerRuntime or {}) do values[key] = value end
  return values
end

function Renderer:updateHandlers()
  if not self.model.handlers then return end
  self.handlerState, self.deferred = Handlers.runExtension(self.model.handlers, 2,
    self:handlerValues(), self.handlerState)
  -- The battle reference resolves render callbacks before skinning too: some
  -- of them alter bones/visibility as well as materials.  Running phase 5 in
  -- drawScene made Muk's posed geometry one frame late (or never applied on
  -- a static frame), even though its textures appeared to update.
  self.handlerState, self.deferred = Handlers.runExtension(self.model.handlers, 5,
    self:handlerValues(), self.handlerState)
end

function Renderer:updatePose(force)
  local anim = self.animIndex and self.model.anims[self.animIndex] or nil
  local frame, finished = sourceFrame(anim, self.time, self.loop)
  local alpha = anim and math.max(0, math.min(0.999999,
    self.time * Pack.FPS - math.floor(self.time * Pack.FPS))) or 0
  if finished then alpha = 0 end
  local changed = force or frame ~= self.frame or finished ~= self.finished
    or math.abs(alpha - (self.poseAlpha or -1)) > 0.000001
  self.frame, self.finished = frame, finished
  self.poseAlpha = alpha
  local mats,pivots = Build.bindMatrices(self.model.bones,
    samplePoseInterpolated(self.model, self.animIndex, frame, alpha, self.loop))
  self.handlerRuntime = type(self.handlerRuntime) == "table" and self.handlerRuntime or {}
  self.handlerRuntime.dynamicObjectEmitters = Renderer.dynamicObjectEmitters(self.model, mats)
  self:updateHandlers()
  if not changed then return false end
  for _, item in pairs(self.handlerState and self.handlerState.operations or {}) do
    local transform = item.result and item.result.transform
    local bone = item.record and item.record.bone
    local matrix = bone and mats[bone + 1] or nil
    if transform and matrix then
      matrix[1][4] = matrix[1][4] + transform.x * 8
      matrix[2][4] = matrix[2][4] + transform.y * 8
      matrix[3][4] = matrix[3][4] + transform.z * 8
      for row = 1, 3 do for col = 1, 3 do matrix[row][col] = matrix[row][col] * transform.scale end end
    end
  end
  local root = self.model.rootScale or 1
  self.handlerBoneAnchors = {}
  for key, item in pairs(self.handlerState and self.handlerState.operations or {}) do
    if item.result and item.result.operation == "dynamic-object-renderer" then
      local bone = item.record and item.record.bone
      local matrix = bone and mats[bone + 1] or nil
      if matrix then
        self.handlerBoneAnchors[key] = {
          matrix[1][4] * root, matrix[2][4] * root, matrix[3][4] * root,
        }
      end
    end
  end
  local hidden = self.handlerState and self.handlerState.bit0ByBone or nil
  for _, part in ipairs(self.parts) do
    local prim, rows = part.prim, part.rows
    for k = 1, prim.nverts do
      local bi = prim.skin[k] + 1
      local m = mats[bi]
      local normalM=pivots and pivots[bi] or m
      local row = rows[k]
      local visible = not (hidden and hidden[prim.skin[k]] == false)
      part.visible[k] = m ~= nil and visible
      if m and visible then
        local x, y, z = prim.pos[k * 3 - 2], prim.pos[k * 3 - 1], prim.pos[k * 3]
        row[1] = (m[1][1] * x + m[1][2] * y + m[1][3] * z + m[1][4]) * root
        row[2] = (m[2][1] * x + m[2][2] * y + m[2][3] * z + m[2][4]) * root
        row[3] = (m[3][1] * x + m[3][2] * y + m[3][3] * z + m[3][4]) * root
        local nx, ny, nz = prim.nrm[k * 3 - 2], prim.nrm[k * 3 - 1], prim.nrm[k * 3]
        row[6], row[7], row[8] = normalize3(
          normalM[1][1] * nx + normalM[1][2] * ny + normalM[1][3] * nz,
          normalM[2][1] * nx + normalM[2][2] * ny + normalM[2][3] * nz,
          normalM[3][1] * nx + normalM[3][2] * ny + normalM[3][3] * nz)
      else
        row[1], row[2], row[3] = 0, 0, 0
        row[6], row[7], row[8] = 0, 1, 0
      end
    end
    if part.mesh and part.mesh.setVertices then pcall(part.mesh.setVertices, part.mesh, rows) end
    if part.mesh and part.mesh.setVertexMap then
      local map = {}
      for ii = 1, #prim.idx, 3 do
        local a, b, c = prim.idx[ii], prim.idx[ii + 1], prim.idx[ii + 2]
        if a and b and c then
          local sa, sb, sc = prim.skin[a] or 0, prim.skin[b] or 0, prim.skin[c] or 0
          if not hidden or (hidden[sa] ~= false and hidden[sb] ~= false and hidden[sc] ~= false) then
            map[#map + 1], map[#map + 2], map[#map + 3] = a, b, c
          end
        end
      end
      pcall(part.mesh.setVertexMap, part.mesh, map)
    end
  end
  if self.anchorEnabled and self.bindAnchor and anim then
    local now=self:geometryAnchor()
    local dx,dy,dz=now[1]-self.bindAnchor[1],now[2]-self.bindAnchor[2],now[3]-self.bindAnchor[3]
    local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
    local allow=math.max(.001,(tonumber(self.model.height) or 1)*.75)
    local tx,ty,tz=0,0,0
    if dist>allow then
      local k=(dist-allow)/dist;tx,ty,tz=dx*k,dy*k,dz*k
    end
    local dt=self.poseDT
    local a=dt and dt>0 and (1-.5^(dt/.05)) or 1
    self.anchorX=(self.anchorX or tx)+(tx-(self.anchorX or tx))*a
    self.anchorY=(self.anchorY or ty)+(ty-(self.anchorY or ty))*a
    self.anchorZ=(self.anchorZ or tz)+(tz-(self.anchorZ or tz))*a
    if self.anchorX~=0 or self.anchorY~=0 or self.anchorZ~=0 then
      for _,part in ipairs(self.parts) do
        for i,row in ipairs(part.rows) do
          if part.used[i] and part.visible[i]~=false then
            row[1]=row[1]-self.anchorX;row[2]=row[2]-self.anchorY;row[3]=row[3]-self.anchorZ
          end
        end
        if part.mesh and part.mesh.setVertices then pcall(part.mesh.setVertices,part.mesh,part.rows) end
      end
    end
  end
  return true
end

function Renderer:poseBounds()
  local minX, minY, minZ = math.huge, math.huge, math.huge
  local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
  local count = 0
  for _, part in ipairs(self.parts) do
    for i, row in ipairs(part.rows) do
      if part.used[i] and part.visible[i] ~= false then
        local x, y, z = row[1], row[2], row[3]
        if x and y and z then
          if x < minX then minX = x end
          if y < minY then minY = y end
          if z < minZ then minZ = z end
          if x > maxX then maxX = x end
          if y > maxY then maxY = y end
          if z > maxZ then maxZ = z end
          count = count + 1
        end
      end
    end
  end
  if count == 0 then
    return { minX = -0.5, minY = -0.5, minZ = -0.5, maxX = 0.5, maxY = 0.5, maxZ = 0.5, cx = 0, cy = 0, cz = 0, radius = 1 }
  end
  local cx, cy, cz = (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5
  local rx, ry, rz = (maxX - minX) * 0.5, (maxY - minY) * 0.5, (maxZ - minZ) * 0.5
  local radius = math.max(sqrt(rx * rx + ry * ry + rz * rz), 0.001)
  return { minX = minX, minY = minY, minZ = minZ, maxX = maxX, maxY = maxY, maxZ = maxZ, cx = cx, cy = cy, cz = cz, radius = radius }
end

function Renderer:fitCamera(width, height, options)
  options = type(options) == "table" and options or {}
  local bounds = options.dynamicFit and self:poseBounds() or self.bindBounds or self:poseBounds()
  local scale = tonumber(options.scale) or 1
  local aspect = math.max(0.001, width / math.max(1, height))
  local verticalHalf = self.fov * 0.5
  local horizontalHalf = math.atan(math.tan(verticalHalf) * aspect)
  local limitingHalf = math.min(verticalHalf, horizontalHalf)
  local padding = math.max(1.01, tonumber(options.fitPadding) or 1.12)
  local radius = math.max(bounds.radius * math.abs(scale), 0.001)
  local zoom = math.max(0.2, math.min(3.2, tonumber(options.zoom) or 1))
  local baseDistance = radius / math.max(0.001, math.sin(limitingHalf)) * padding
  local distance = baseDistance / zoom
  local near = math.max(0.001, distance - radius * 1.15)
  local far = math.max(near + 0.01, distance + radius * 3.0)
  return {
    bounds = bounds, scale = scale, aspect = aspect, zoom = zoom,
    distance = distance, near = near, far = far,
  }
end

function Renderer:step(dt)
  self.poseDT=math.max(0,tonumber(dt) or 0)
  self.time = self.time + math.max(0, tonumber(dt) or 0)
  self:updatePose(false)
  self.poseDT=nil
  return not self.finished
end

-- Seek in source-authored 30 Hz frames. This is primarily useful to model
-- inspection tools, but keeping it on the renderer means callback texture
-- streams and handler phases are refreshed by the same path as playback.
function Renderer:seekFrame(frame)
  local anim = self.animIndex and self.model.anims[self.animIndex] or nil
  if not anim or (anim.frames or 0) <= 0 then return false end
  frame = floor(tonumber(frame) or 0) % anim.frames
  self.time = frame / Pack.FPS
  self.frame = -1
  self.finished = false
  self:updatePose(true)
  return true
end

local function callbackRecord(model, site)
  for _, record in ipairs(model and model.handlers and model.handlers.records or {}) do
    if tonumber(record.commandOffset) == tonumber(site) then return record end
  end
end

function Renderer:callbackOwnsTexture(prim)
  if not prim or not prim.callbackOffset then return false end
  if prim.callbackTextureRequired then return true end
  local record = callbackRecord(self.model, prim.callbackOffset)
  if not record then return false end
  if record.descriptor == 0x81000050 then return true end
  if record.descriptor == DualTexture.DESCRIPTOR then
    -- Command 0x08 decorates the complete preceding draw. Its generated
    -- material replaces body inputs; alpha face decals establish a local
    -- authored material and remain outside the callback.
    return DualTexture.ownsPrimitive(prim, record.descriptor)
  end
  return false
end

function Renderer:callbackUsesMaterialFx(prim)
  if not prim or prim.decal or not prim.callbackOffset then return false end
  local record = callbackRecord(self.model, prim.callbackOffset)
  -- Texture ownership and material ownership are intentionally separate.
  -- The slime builder's second scrolling layer affects body surfaces even
  -- when their authored primary texture contains detail. Alpha eye/mouth
  -- decals remain outside the body material.
  return record ~= nil and record.descriptor == DualTexture.DESCRIPTOR
end

function Renderer:currentTexture(prim)
  local dynamic = self.handlerState and self.handlerState.textureBySite
  local site = prim and prim.callbackOffset
  if dynamic and site and dynamic[site]
      and self:callbackOwnsTexture(prim) then
    return dynamic[site]
  end
  return Pack.textureIndex(self.model,prim,self.animIndex,self.frame,self.auxIndex,
    self.handlerRuntime and self.handlerRuntime.callbackFrame)
end

-- Fragment UVs are normalized against the authored texture before DSM
-- packing, and the authored sampler shift is baked into each mesh. A render
-- callback can replace that texture with a differently-sized image and its
-- own zero-shift tile. Convert back to the same raw N64 S/T coordinate space
-- before sampling the callback image.
function Renderer.callbackTextureCoordinateScale(model, prim, textureIndex)
  if type(prim) ~= "table" or not textureIndex then return 1, 1 end
  local source = model and model.textures and model.textures[prim.tex]
  local target = model and model.textures and model.textures[textureIndex]
  if not target then return 1, 1 end
  local sourceW = source and tonumber(source.w) or 32
  local sourceH = source and tonumber(source.h) or 32
  local targetW = math.max(1, tonumber(target.w) or 32)
  local targetH = math.max(1, tonumber(target.h) or 32)
  local us, vs = Sampler.uvScale(prim.sampler, prim.textureScale)
  if us == 0 then us = 1 end
  if vs == 0 then vs = 1 end
  return sourceW / targetW / us, sourceH / targetH / vs
end

function Renderer:worldMetrics()
  local model = self.model or {}
  local bounds = self.bindBounds or self:poseBounds()
  return {
    height = math.max(0.001, tonumber(model.height) or (bounds.maxY - bounds.minY)),
    floor = tonumber(model.floor) or bounds.minY,
    radius = math.max(0.001, tonumber(model.radius) or bounds.radius),
    rootScale = tonumber(model.rootScale) or 1,
    bounds = bounds,
  }
end

-- Draw into the caller's currently-bound color/depth target. The battle scene
-- uses this path so every actor shares the same camera and depth buffer.
function Renderer.koffingGasGeometryState(particle, anchor, sourceGeometry, textureWidth, textureHeight)
  return EffectRenderer.billboardGeometry(particle, anchor, sourceGeometry, textureWidth, textureHeight)
end

function Renderer.koffingGasMaterialState(age)
  local state = assert(EffectRenderer.materialState(109, age))
  state.gasMode = state.effectIntensityMode
  return state
end

local function dynamicObjectRecord(model, site)
  local records = model and model.handlers and model.handlers.records
  if not site or type(records) ~= "table" then return nil end
  for _, record in ipairs(records) do
    if tonumber(record.commandOffset) == tonumber(site)
        and record.family == "dynamic-object-renderer" then return record end
  end
end

local function dynamicObjectCarrier(model, prim)
  local site = tonumber(prim and prim.callbackOffset)
  if dynamicObjectRecord(model, site) == nil then return false end
  local primitiveIndex
  for index, candidate in ipairs(model and model.prims or {}) do
    if candidate == prim then primitiveIndex=index break end
  end
  return DynamicObject.isCarrierPrimitive(model and model.species, primitiveIndex)
end

function Renderer.dynamicObjectEmitters(model, matrices)
  local emitters, seen = {}, {}
  if type(model) ~= "table" or type(matrices) ~= "table" then return emitters end
  local root = tonumber(model.rootScale) or 1
  local referenceMatrix = matrices[2] or matrices[1]
  local reference = referenceMatrix and {
    referenceMatrix[1][4] * root,
    referenceMatrix[2][4] * root,
    referenceMatrix[3][4] * root,
  } or {0,0,0}
  local profile = DynamicObject.profile(model.species)
  if not profile then return emitters end
  if profile.emitters == "carrier-skin" then
    for _, prim in ipairs(model.prims or {}) do if dynamicObjectCarrier(model, prim) then
      for _, bone in ipairs(prim.skin or {}) do
        bone = math.floor(tonumber(bone) or -1)
        local matrix = matrices[bone + 1]
        if bone >= 0 and matrix and not seen[bone] then
          seen[bone] = true
          emitters[#emitters + 1] = {
            index = #emitters,
            bone = bone,
            origin = {
              matrix[1][4] * root,
              matrix[2][4] * root,
              matrix[3][4] * root,
            },
            reference = {reference[1], reference[2], reference[3]},
          }
        end
      end
    end end
  else
    for _, record in ipairs(model.handlers and model.handlers.records or {}) do
      if record.family == "dynamic-object-renderer" then
        local bone = math.floor(tonumber(record.bone) or -1)
        local matrix = matrices[bone + 1]
        if bone >= 0 and matrix and not seen[bone] then
          seen[bone] = true
          emitters[#emitters + 1] = { index=#emitters, bone=bone,
            origin={matrix[1][4]*root,matrix[2][4]*root,matrix[3][4]*root},
            reference={reference[1],reference[2],reference[3]} }
        end
      end
    end
  end
  return emitters
end

function Renderer.primitiveRenderState(model, prim, options)
  options = type(options) == "table" and options or {}
  local carrier = dynamicObjectCarrier(model, prim)
  return {
    dynamicObjectCarrier = carrier,
    -- Carrier profiles contain merged callback billboard copies, not ordinary
    -- body geometry. Mixed profiles classify individual payload primitives so
    -- callback-inheriting body meshes remain in the static/shadow passes.
    drawStatic = not carrier,
    cullEnabled = prim and prim.cull == true
      and (carrier or options.disableCulling ~= true),
    lightingEnabled = not carrier and (prim == nil or prim.lighting ~= false),
    castsShadow = not carrier,
    textureGenEnabled = prim and math.floor((prim.geometryMode or 0) / 0x40000) % 2 == 1,
  }
end

function Renderer:drawDynamicObjects(pass, model, options)
  if pass ~= "additive" or self.debugSuppressDynamicObjects then return end
  local g = love and love.graphics
  if not g then return end
  local dynamic = self.handlerState and self.handlerState.dynamicObjectsBySite
  if type(dynamic) ~= "table" then return end
  local metrics = self:worldMetrics()
  for site, effect in pairs(dynamic) do
    if effect.family == "dynamic-object" or effect.family == "koffing-gas" then
      local bounds = metrics.bounds or {}
      local fallbackAnchor = self.handlerBoneAnchors and self.handlerBoneAnchors[site] or {
        ((bounds.minX or 0) + (bounds.maxX or 0)) * 0.5,
        ((bounds.minY or 0) + (bounds.maxY or 0)) * 0.5,
        ((bounds.minZ or 0) + (bounds.maxZ or 0)) * 0.5,
      }
      if g.setMeshCullMode then g.setMeshCullMode("none") end
      if g.setDepthMode then g.setDepthMode(RenderContract.DYNAMIC_DEPTH_COMPARE, false) end
      if g.setBlendMode then g.setBlendMode("alpha", "alphamultiply") end
      pcall(self.shader.send, self.shader, "secondaryEnabled", 0)
      pcall(self.shader.send, self.shader, "textureScroll", {0,0,0,0})
      sendTextureWrapMode(self.shader, "primaryWrapMode", "clamp", "clamp")
      sendTextureWrapMode(self.shader, "secondaryWrapMode", "clamp", "clamp")
      pcall(self.shader.send, self.shader, "boundedUVEnabled",
        self.boundedTextureUV and 1 or 0)
      pcall(self.shader.send, self.shader, "environmentMix", 0)
      pcall(self.shader.send, self.shader, "alphaCutoff", 0.001)
      pcall(self.shader.send, self.shader, "effectIntensityMode", 1)
      if g.setColor then g.setColor(1,1,1,1) end
      local emitters = effect.emitters
      if type(emitters) ~= "table" or #emitters == 0 then
        emitters = {{ index = 0, particles = effect.particles, origin = fallbackAnchor }}
      end
      for emitterIndex, emitter in ipairs(emitters) do
        local anchor = emitter.origin or fallbackAnchor
        for i = 1, 10 do
          local particle = emitter.particles and emitter.particles[i]
          if particle and particle.active then
            local materialState = EffectRenderer.materialState(effect.species or 109,
              particle.age, self.handlerRuntime)
            local frame = materialState and materialState.frame or 1
            frame = math.max(1, math.min(#(effect.textureSlots or {}), frame))
            local textureIndex = effect.textureSlots and effect.textureSlots[frame]
            local texture = textureIndex and Pack.image(self.model, textureIndex) or nil
            if texture then
              local meshKey = site .. ":" .. emitterIndex .. ":" .. i
              local entry = self.dynamicMeshes[meshKey]
              if not entry then
                local mesh, rows = makeDynamicMesh()
                entry = { mesh = mesh, rows = rows }
                self.dynamicMeshes[meshKey] = entry
              end
              if entry.mesh then
                local tw,th=imageDimensions(texture,self.model.textures[textureIndex])
                local geometry = EffectRenderer.billboardGeometry(particle, anchor, effect.geometry, tw, th)
                local rows = entry.rows
                for vi = 1, 4 do
                  local source = geometry.vertices[vi]
                  rows[vi][1],rows[vi][2],rows[vi][3]=source[1],source[2],source[3]
                  rows[vi][4],rows[vi][5]=source[4],source[5]
                end
                if entry.mesh.setVertices then pcall(entry.mesh.setVertices,entry.mesh,rows) end
                if entry.mesh.setTexture then pcall(entry.mesh.setTexture,entry.mesh,texture) end
                if texture.setFilter then pcall(texture.setFilter,texture,self.textureFilter,self.textureFilter,self.anisotropy) end
                if texture.setWrap then pcall(texture.setWrap,texture,"clamp","clamp") end
                pcall(self.shader.send,self.shader,"primarySize",{tw,th})
                pcall(self.shader.send,self.shader,"primitiveColor",materialState.primitiveColor)
                pcall(self.shader.send,self.shader,"environmentColor",materialState.environmentColor)
                if g.setColor then g.setColor(1,1,1,1) end
                g.draw(entry.mesh)
              end
            end
          end
        end
      end
      if g.setColor then g.setColor(1,1,1,1) end
      pcall(self.shader.send, self.shader, "effectIntensityMode", 0)
    end
  end
end

function Renderer:drawScene(pass, model, options)
  options = type(options) == "table" and options or {}
  local g = love and love.graphics
  if not (g and self.shader) then return false, "graphics unavailable" end
  local vp = options.viewProjection
  if type(vp) ~= "table" or type(model) ~= "table" then
    return false, "shared scene matrices required"
  end
  local additiveOnly = pass == "additive"
  local opaqueOnly = pass == "opaque"
  local ok, err = pcall(function()
    g.setShader(self.shader)
    pcall(self.shader.send, self.shader, "mvp", "row", matMul(vp, model))
    pcall(self.shader.send, self.shader, "modelMatrix", "row", model)
    pcall(self.shader.send, self.shader, "viewMatrix", "row", options.viewMatrix or identity())
    pcall(self.shader.send, self.shader, "normalMatrix", "row",
      options.normalMatrix or {1,0,0, 0,1,0, 0,0,1})
    pcall(self.shader.send, self.shader, "lightDir", options.lightDir or self.lightDir)
    pcall(self.shader.send, self.shader, "ambient", options.ambient or self.ambient)
    pcall(self.shader.send, self.shader, "diffuse", options.diffuse or self.diffuse)
    pcall(self.shader.send, self.shader, "secondaryEnabled", 0)
    pcall(self.shader.send, self.shader, "secondaryMix", 100/255)
    pcall(self.shader.send, self.shader, "primarySize", {1,1})
    pcall(self.shader.send, self.shader, "secondarySize", {1,1})
    pcall(self.shader.send, self.shader, "textureScroll", {0,0,0,0})
    pcall(self.shader.send, self.shader, "alphaCutoff", 0.01)
    pcall(self.shader.send, self.shader, "sceneTint", options.tint or {1,1,1,1})
    pcall(self.shader.send, self.shader, "flashAmount", options.flashAmount or 0)
    pcall(self.shader.send, self.shader, "effectIntensityMode", 0)
    pcall(self.shader.send, self.shader, "lightingEnabled", 1)
    pcall(self.shader.send, self.shader, "celShadingEnabled",
      self:currentShaderStyle() == "cel" and 1 or 0)
    pcall(self.shader.send, self.shader, "textureGenEnabled", 0)
    pcall(self.shader.send, self.shader, "textureCoordinateScale", {1,1})
    pcall(self.shader.send, self.shader, "textureGenScale", {1,1})
    pcall(self.shader.send, self.shader, "decalDepthBias", 0)
    sendTextureWrapMode(self.shader, "primaryWrapMode", "clamp", "clamp")
    sendTextureWrapMode(self.shader, "secondaryWrapMode", "clamp", "clamp")
    pcall(self.shader.send, self.shader, "boundedUVEnabled",
      self.boundedTextureUV and 1 or 0)
    pcall(self.shader.send, self.shader, "sunVP", "row", options.sunVP or identity())
    pcall(self.shader.send, self.shader, "sunEnabled",
      options.sunMap and self.receiveModelSunShadows and 1 or 0)
    if options.sunMap then pcall(self.shader.send,self.shader,"sunMap",options.sunMap) end
    pcall(self.shader.send,self.shader,"sunDark",options.sunDark or 0.68)
    pcall(self.shader.send,self.shader,"sunBias",options.sunBias or 0.002)
    pcall(self.shader.send,self.shader,"sunTexel",options.sunTexel or {1/1024,1/1024})
    -- Keep ordinary geometry on strict depth comparison so eye decals cannot
    -- leak through nearer beaks or muzzles. Alpha decal primitives switch to
    -- equal-depth comparison without writing depth when they are drawn.
    if g.setDepthMode then
      g.setDepthMode(RenderContract.MODEL_DEPTH_COMPARE, not additiveOnly)
    end
    if g.setBlendMode then
      g.setBlendMode(additiveOnly and "add" or "alpha", "alphamultiply")
    end
    for partIndex, part in ipairs(self.parts) do
      local additive = part.prim.additive == true
      local renderState = Renderer.primitiveRenderState(self.model, part.prim, options)
      if part.mesh and renderState.drawStatic
          and (not self.debugOnlyPrimitive or self.debugOnlyPrimitive == partIndex)
          and ((additiveOnly and additive) or (opaqueOnly and not additive)
          or (not additiveOnly and not opaqueOnly)) then
        if g.setMeshCullMode then
          local front = self.flipY ~= (options.flipWinding == true)
          g.setMeshCullMode(renderState.cullEnabled
            and (front and "front" or "back") or "none")
        end
        local texture = Pack.image(self.model, self:currentTexture(part.prim))
        local site = part.prim.callbackOffset
        local dynamic = self.handlerState and self.handlerState.materialBySite
        local material = site and dynamic and dynamic[site] or part.prim.material
        local attributes = self.handlerState and self.handlerState.attributesBySite
        local attribute = site and attributes and attributes[site]
        local color = attribute and attribute.color or
          (material and material.primitiveColor) or {1,1,1,1}
        pcall(self.shader.send, self.shader, "effectIntensityMode",
          material and material.intensity and 1 or 0)
        pcall(self.shader.send, self.shader, "primitiveColor", color)
        pcall(self.shader.send, self.shader, "lightingEnabled",
          renderState.lightingEnabled and 1 or 0)
        if g.setDepthMode then
          local compare, write = RenderContract.depthState(part.prim, not additiveOnly)
          g.setDepthMode(compare, write)
        end
        pcall(self.shader.send,self.shader,"decalDepthBias",
          part.prim.decal and self.decalDepthBias or 0)
        pcall(self.shader.send, self.shader, "environmentColor",
          material and material.environmentColor or {1,1,1,1})
        pcall(self.shader.send, self.shader, "environmentMix",
          material and material.combine and
          (material.combine[1] ~= 0 or material.combine[2] ~= 0) and 1 or 0)
        local sets = self.handlerState and self.handlerState.textureSetBySite
        local set = self:callbackUsesMaterialFx(part.prim)
          and site and sets and sets[site] or nil
        local textureIndex = self:currentTexture(part.prim)
        local wrapS, wrapT = resolvedTextureWrap(part.prim, material, set)
        sendTextureWrapMode(self.shader, "primaryWrapMode", wrapS, wrapT)
        local uvScaleS, uvScaleT = 1, 1
        if set then
          uvScaleS, uvScaleT = Renderer.callbackTextureCoordinateScale(
            self.model, part.prim, textureIndex)
        end
        pcall(self.shader.send, self.shader, "textureCoordinateScale",
          {uvScaleS, uvScaleT})
        local secondary = set and Pack.image(self.model, set[2]) or nil
        if secondary then
          local secondaryWrapS = set.wrap or "clamp"
          local secondaryWrapT = set.wrap or "clamp"
          sendTextureWrapMode(self.shader, "secondaryWrapMode",
            secondaryWrapS, secondaryWrapT)
          if secondary.setWrap and set.wrap then
            pcall(secondary.setWrap, secondary, set.wrap, set.wrap)
          end
          pcall(self.shader.send, self.shader, "secondaryTexture", secondary)
          local sw, sh = imageDimensions(secondary,self.model.textures[set[2]])
          pcall(self.shader.send, self.shader, "secondarySize", {sw,sh})
          pcall(self.shader.send, self.shader, "secondaryMix", set.mix or 100/255)
          local a, b = set.scroll and set.scroll[1], set.scroll and set.scroll[2]
          local aS, aT = foldedTextureScroll(a, wrapS, wrapT,
            self.boundedTextureUV)
          local bS, bT = foldedTextureScroll(b, secondaryWrapS, secondaryWrapT,
            self.boundedTextureUV)
          pcall(self.shader.send, self.shader, "textureScroll", {
            aS, aT, bS, bT})
          pcall(self.shader.send, self.shader, "secondaryEnabled", 1)
        else
          pcall(self.shader.send, self.shader, "secondaryEnabled", 0)
          sendTextureWrapMode(self.shader, "secondaryWrapMode", "clamp", "clamp")
          pcall(self.shader.send, self.shader, "textureScroll", {0,0,0,0})
        end
        pcall(self.shader.send, self.shader, "alphaCutoff", additive and 0.001 or 0.01)
        if texture then
          if texture.setFilter then pcall(texture.setFilter, texture, self.textureFilter,
            self.textureFilter, self.anisotropy) end
          if texture.setWrap then
            pcall(texture.setWrap, texture, wrapS, wrapT)
          end
          local tw, th = imageDimensions(texture,
            self.model.textures[self:currentTexture(part.prim)])
          pcall(self.shader.send, self.shader, "primarySize", {tw,th})
          local gs, gt = Sampler.textureGenScale(part.prim.sampler,
            part.prim.textureScale, tw, th)
          pcall(self.shader.send, self.shader, "textureGenScale", {gs,gt})
          pcall(self.shader.send, self.shader, "textureGenEnabled",
            renderState.textureGenEnabled and 1 or 0)
          if part.mesh.setTexture then pcall(part.mesh.setTexture, part.mesh, texture) end
        end
        sendFlameBillboard(self.shader, part, options.viewMatrix, model)
        g.draw(part.mesh)
      end
    end
    self:drawDynamicObjects(pass, model, options)
  end)
  if not ok then return false, tostring(err) end
  return true
end

function Renderer:drawShadowMap(model,lightVP)
  local g=love and love.graphics
  if not (g and self.shadowShader and model and lightVP) then return false,"shadow shader unavailable" end
  local ok,err=pcall(function()
    g.setShader(self.shadowShader)
    if g.setMeshCullMode then g.setMeshCullMode("none") end
    if g.setDepthMode then g.setDepthMode(RenderContract.SHADOW_DEPTH_COMPARE,true) end
    if g.setBlendMode then g.setBlendMode("replace","premultiplied") end
    pcall(self.shadowShader.send,self.shadowShader,"lightVP","row",lightVP)
    pcall(self.shadowShader.send,self.shadowShader,"modelMatrix","row",model)
    for _,part in ipairs(self.parts) do
      local renderState=Renderer.primitiveRenderState(self.model,part.prim)
      if part.mesh and not part.prim.additive and renderState.castsShadow then
        local texture=Pack.image(self.model,self:currentTexture(part.prim))
        if texture and part.mesh.setTexture then pcall(part.mesh.setTexture,part.mesh,texture) end
        g.draw(part.mesh)
      end
    end
  end)
  return ok,ok and nil or tostring(err)
end

function Renderer:drawShadow(model, options)
  options=type(options)=="table" and options or {}
  options.tint=options.tint or {0.02,0.025,0.035,0.34}
  options.ambient=options.ambient or {1,1,1}
  options.diffuse=options.diffuse or {0,0,0}
  return self:drawScene("opaque",model,options)
end

function Renderer:renderToCanvas(width, height, options)
  options = type(options) == "table" and options or {}
  width = math.max(1, floor(tonumber(width) or 96))
  height = math.max(1, floor(tonumber(height) or 96))
  if not (love and love.graphics) then return nil, "graphics unavailable" end
  local msaa = math.max(0, floor(tonumber(options.msaa) or 4))
  if not self.canvas or self.canvasW ~= width or self.canvasH ~= height or self.canvasMSAA ~= msaa then
    if self.canvas and self.canvas.release then pcall(self.canvas.release, self.canvas) end
    if self.depth and self.depth.release then pcall(self.depth.release, self.depth) end
    self.canvas, self.depth, self.temporaryDepth = makeCanvas(width, height, msaa)
    self.canvasW, self.canvasH, self.canvasMSAA = width, height, msaa
  end
  if not self.canvas then return nil, "canvas unavailable" end

  local g = love.graphics
  local oldCanvas = g.getCanvas and { g.getCanvas() } or nil
  local oldShader = g.getShader and g.getShader() or nil
  local oldBlend, oldAlpha
  if g.getBlendMode then oldBlend, oldAlpha = g.getBlendMode() end
  local oldDepthCompare, oldDepthWrite
  if g.getDepthMode then oldDepthCompare, oldDepthWrite = g.getDepthMode() end
  local oldCull = g.getMeshCullMode and g.getMeshCullMode() or nil
  local ok, err = pcall(function()
    if self.depth then g.setCanvas({self.canvas,depthstencil=self.depth})
    elseif self.temporaryDepth then g.setCanvas({self.canvas,depth=true})
    else g.setCanvas(self.canvas) end
    g.clear(0, 0, 0, 0, true, true)
    -- Match the scene renderer's per-primitive body/decal depth contract.
    if g.setDepthMode then g.setDepthMode(RenderContract.MODEL_DEPTH_COMPARE, true) end
    if self.shader then g.setShader(self.shader) end

    local model = self.model
    local camera = self:fitCamera(width, height, options)
    local bounds = camera.bounds
    local view = lookAt(0, 0, camera.distance, 0, 0, 0)
    local proj = perspective(self.fov, camera.aspect, camera.near, camera.far,
      tonumber(options.panX) or 0, tonumber(options.panY) or 0)
    local mm = modelMatrix(options.yaw or self.yaw, options.pitch or self.pitch,
      camera.scale, bounds.cx, bounds.cy, bounds.cz, self.flipY)
    local mvp = matMul(proj, matMul(view, mm))
    if self.shader then
      pcall(self.shader.send, self.shader, "mvp", "row", mvp)
      pcall(self.shader.send, self.shader, "modelMatrix", "row", mm)
      pcall(self.shader.send, self.shader, "viewMatrix", "row", view)
      pcall(self.shader.send, self.shader, "normalMatrix", "row", normalMatrix(options.yaw or self.yaw, options.pitch or self.pitch, self.flipY))
      pcall(self.shader.send, self.shader, "lightDir", self.lightDir)
      pcall(self.shader.send, self.shader, "ambient", self.ambient)
      pcall(self.shader.send, self.shader, "diffuse", self.diffuse)
      pcall(self.shader.send, self.shader, "secondaryEnabled", 0)
      pcall(self.shader.send, self.shader, "secondaryMix", 100 / 255)
      pcall(self.shader.send, self.shader, "primarySize", {1,1})
      pcall(self.shader.send, self.shader, "secondarySize", {1,1})
      pcall(self.shader.send, self.shader, "textureScroll", { 0, 0, 0, 0 })
      pcall(self.shader.send, self.shader, "alphaCutoff", 0.001)
      pcall(self.shader.send, self.shader, "sceneTint", {1,1,1,1})
      pcall(self.shader.send, self.shader, "flashAmount", 0)
      pcall(self.shader.send, self.shader, "effectIntensityMode", 0)
      pcall(self.shader.send, self.shader, "lightingEnabled", 1)
      pcall(self.shader.send, self.shader, "celShadingEnabled",
        self:currentShaderStyle() == "cel" and 1 or 0)
      pcall(self.shader.send, self.shader, "textureGenEnabled", 0)
      pcall(self.shader.send, self.shader, "textureCoordinateScale", {1,1})
      pcall(self.shader.send, self.shader, "textureGenScale", {1,1})
      pcall(self.shader.send, self.shader, "decalDepthBias", 0)
      sendTextureWrapMode(self.shader, "primaryWrapMode", "clamp", "clamp")
      sendTextureWrapMode(self.shader, "secondaryWrapMode", "clamp", "clamp")
      pcall(self.shader.send, self.shader, "boundedUVEnabled",
        self.boundedTextureUV and 1 or 0)
    end

    local function drawPass(additive)
      if g.setBlendMode then
        if additive then g.setBlendMode("add", "alphamultiply") else g.setBlendMode("alpha", "alphamultiply") end
      end
      for partIndex, part in ipairs(self.parts) do
        local renderState=Renderer.primitiveRenderState(self.model,part.prim)
        if part.mesh and renderState.drawStatic and part.prim.additive == additive
            and (not self.debugOnlyPrimitive or self.debugOnlyPrimitive == partIndex) then
          if g.setMeshCullMode then
            g.setMeshCullMode(part.prim.cull and (self.flipY and "front" or "back") or "none")
          end
          local texture = Pack.image(model, self:currentTexture(part.prim))
          local site = part.prim.callbackOffset
          local dynamic = self.handlerState and self.handlerState.materialBySite
          local material = site and dynamic and dynamic[site] or part.prim.material
          local attributes = self.handlerState and self.handlerState.attributesBySite
          local attribute = site and attributes and attributes[site]
          local primitiveColor = attribute and attribute.color
            or (material and material.primitiveColor) or { 1, 1, 1, 1 }
          local sets = self.handlerState and self.handlerState.textureSetBySite
          local set = self:callbackUsesMaterialFx(part.prim)
            and site and sets and sets[site] or nil
          local textureIndex = self:currentTexture(part.prim)
          local wrapS,wrapT=resolvedTextureWrap(part.prim,material,set)
          if g.setDepthMode then
            local compare, write = RenderContract.depthState(part.prim, not additive)
            g.setDepthMode(compare, write)
          end
          if self.shader then
            pcall(self.shader.send,self.shader,"decalDepthBias",
              part.prim.decal and self.decalDepthBias or 0)
          end
          if self.shader then
            pcall(self.shader.send, self.shader, "effectIntensityMode",
              material and material.intensity and 1 or 0)
            pcall(self.shader.send, self.shader, "primitiveColor",
              primitiveColor)
            pcall(self.shader.send, self.shader, "environmentColor",
              material and material.environmentColor or { 1, 1, 1, 1 })
            pcall(self.shader.send, self.shader, "environmentMix",
              material and material.combine and (material.combine[1] ~= 0 or material.combine[2] ~= 0) and 1 or 0)
            sendTextureWrapMode(self.shader,"primaryWrapMode",wrapS,wrapT)
            local uvScaleS,uvScaleT=1,1
            if set then
              uvScaleS,uvScaleT=Renderer.callbackTextureCoordinateScale(
                model,part.prim,textureIndex)
            end
            pcall(self.shader.send,self.shader,"textureCoordinateScale",
              {uvScaleS,uvScaleT})
            local secondary = set and Pack.image(model, set[2]) or nil
            if secondary then
              local secondaryWrapS=set.wrap or "clamp"
              local secondaryWrapT=set.wrap or "clamp"
              sendTextureWrapMode(self.shader,"secondaryWrapMode",
                secondaryWrapS,secondaryWrapT)
              if secondary.setWrap and set.wrap then
                pcall(secondary.setWrap, secondary, set.wrap, set.wrap)
              end
              pcall(self.shader.send, self.shader, "secondaryTexture", secondary)
              local sw,sh=imageDimensions(secondary,model.textures[set[2]])
              pcall(self.shader.send, self.shader, "secondarySize", {sw,sh})
              pcall(self.shader.send, self.shader, "secondaryMix", set.mix or (100 / 255))
              local a, b = set.scroll and set.scroll[1], set.scroll and set.scroll[2]
              local aS,aT=foldedTextureScroll(a,wrapS,wrapT,
                self.boundedTextureUV)
              local bS,bT=foldedTextureScroll(b,secondaryWrapS,secondaryWrapT,
                self.boundedTextureUV)
              pcall(self.shader.send, self.shader, "textureScroll", {
                aS,aT,bS,bT,
              })
              pcall(self.shader.send, self.shader, "secondaryEnabled", 1)
            else
              pcall(self.shader.send, self.shader, "secondaryEnabled", 0)
              sendTextureWrapMode(self.shader,"secondaryWrapMode","clamp","clamp")
              pcall(self.shader.send, self.shader, "textureScroll", { 0, 0, 0, 0 })
            end
            pcall(self.shader.send, self.shader, "alphaCutoff", additive and 0.001 or 0.01)
          end
          if texture and texture.setFilter then
            pcall(texture.setFilter, texture, self.textureFilter, self.textureFilter, self.anisotropy)
          end
          if texture then
            local tw,th=imageDimensions(texture,
              model.textures[self:currentTexture(part.prim)])
            pcall(self.shader.send, self.shader, "primarySize", {tw,th})
            local gs,gt=Sampler.textureGenScale(part.prim.sampler,
              part.prim.textureScale,tw,th)
            pcall(self.shader.send,self.shader,"textureGenScale",{gs,gt})
            pcall(self.shader.send,self.shader,"textureGenEnabled",
              renderState.textureGenEnabled and 1 or 0)
          end
          if texture and texture.setWrap then
            pcall(texture.setWrap,texture,wrapS,wrapT)
          end
          if texture and part.mesh.setTexture then pcall(part.mesh.setTexture, part.mesh, texture) end
          sendFlameBillboard(self.shader, part, view, mm)
          g.draw(part.mesh)
        end
      end
    end
    drawPass(false)
    drawPass(true)
    self:drawDynamicObjects("additive", mm, {viewMatrix=view})

  end)
  if oldCull and g.setMeshCullMode then pcall(g.setMeshCullMode, oldCull) end
  if oldDepthCompare and g.setDepthMode then pcall(g.setDepthMode, oldDepthCompare, oldDepthWrite) end
  if g.setBlendMode then pcall(g.setBlendMode, oldBlend or "alpha", oldAlpha or "alphamultiply") end
  if g.setShader then pcall(g.setShader, oldShader) end
  if oldCanvas and #oldCanvas > 0 then
    pcall(g.setCanvas, unpack(oldCanvas))
  elseif g.setCanvas then
    pcall(g.setCanvas)
  end
  if not ok then return nil, tostring(err) end
  return self.canvas
end

function Renderer:draw(x, y, width, height, options)
  options = type(options) == "table" and options or {}
  width = math.max(1, tonumber(width) or 96)
  height = math.max(1, tonumber(height) or 96)
  local supersample = math.max(1, math.min(3, tonumber(options.supersample) or 1))
  local rw = math.max(1, floor(width * supersample + 0.5))
  local rh = math.max(1, floor(height * supersample + 0.5))
  local canvas, err = self:renderToCanvas(rw, rh, options)
  if not canvas then return false, err end
  if not (love and love.graphics and love.graphics.draw) then return false, "graphics unavailable" end
  local g = love.graphics
  if g.setColor then g.setColor(1, 1, 1, 1) end
  g.draw(canvas, tonumber(x) or 0, tonumber(y) or 0, 0, width / rw, height / rh)
  return true
end

function Renderer:release()
  for _, part in ipairs(self.parts or {}) do
    if part.mesh and part.mesh.release then pcall(part.mesh.release, part.mesh) end
    part.mesh = nil
  end
  for _, entry in pairs(self.dynamicMeshes or {}) do
    if entry.mesh and entry.mesh.release then pcall(entry.mesh.release, entry.mesh) end
    entry.mesh = nil
  end
  self.dynamicMeshes = {}
  if self.canvas and self.canvas.release then pcall(self.canvas.release, self.canvas) end
  if self.depth and self.depth.release then pcall(self.depth.release, self.depth) end
  if self.shader and self.shader.release then pcall(self.shader.release, self.shader) end
  if self.shadowShader and self.shadowShader.release then pcall(self.shadowShader.release,self.shadowShader) end
  self.canvas, self.depth, self.temporaryDepth, self.shader, self.shadowShader =
    nil, nil, nil, nil, nil
end

Renderer.sourceFrame = sourceFrame
Renderer.samplePose = samplePose
Renderer.samplePoseInterpolated = samplePoseInterpolated
Renderer.angleDelta = angleDelta
Renderer.BREAK_ANGLE = BREAK_ANGLE
Renderer.BREAK_MOVE = BREAK_MOVE
Renderer.matMul = matMul
Renderer.perspective = perspective
Renderer.lookAt = lookAt
Renderer.modelMatrix = modelMatrix
Renderer.normalMatrix = normalMatrix
Renderer.identity = identity
Renderer.sendFlameBillboard = sendFlameBillboard

function Renderer.ortho(l,r,b,t,n,f)
  return {2/(r-l),0,0,-(r+l)/(r-l), 0,2/(t-b),0,-(t+b)/(t-b),
    0,0,-2/(f-n),-(f+n)/(f-n), 0,0,0,1}
end

return Renderer
