package.path = "./?.lua;./?/init.lua;" .. package.path

local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local checks, failures = 0, 0
local function check(value, name)
  checks = checks + 1
  if value then
    print("PASS " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name)
  end
end

local function near(a, b)
  return math.abs((a or 0) - (b or 0)) < 1e-9
end

check(Sampler.wrapCode("clamp") == 0, "clamp shader wrap code")
check(Sampler.wrapCode("repeat") == 1, "repeat shader wrap code")
check(Sampler.wrapCode("mirroredrepeat") == 2, "mirrored-repeat shader wrap code")
check(near(Sampler.foldOffset(37.25, "repeat"), 0.25),
  "repeat scroll is folded into one tile")
check(near(Sampler.foldOffset(-12.25, "repeat"), 0.75),
  "negative repeat scroll preserves periodic position")
check(near(Sampler.foldOffset(37.25, "mirroredrepeat"), 1.25),
  "mirrored-repeat scroll is folded into its two-tile period")
check(near(Sampler.foldOffset(-0.25, "mirroredrepeat"), 1.75),
  "negative mirrored-repeat scroll preserves parity")
check(near(Sampler.foldOffset(37.25, "clamp"), 37.25),
  "clamp scroll keeps absolute position")
check(Sampler.coordinateAnchor(27.82, 32.46, "repeat") == 30,
  "repeat mesh coordinates use a whole-tile origin")
check(Sampler.coordinateAnchor(17.1, 22.4, "mirroredrepeat") == 18,
  "mirrored-repeat mesh origin preserves even-tile parity")
check(Sampler.coordinateAnchor(17.1, 22.4, "clamp") == 0,
  "clamped mesh coordinates retain their absolute origin")
do
  local prim={nverts=3,uv={27.25,18.25,28.5,19.5,29.75,20.75},
    sampler={cms=0,cmt=1}}
  local rows,anchorU,anchorV=Renderer.meshRows(prim)
  check(anchorU==28 and anchorV==18,
    "mesh origin is removed before mobile interpolation")
  check(near(rows[1][4],-0.75) and near(rows[1][5],0.25),
    "mesh UV stays in a small precision-safe range")
  check(near(Sampler.foldOffset(rows[1][4],"repeat"),
      Sampler.foldOffset(prim.uv[1],"repeat"))
    and near(Sampler.foldOffset(rows[1][5],"mirroredrepeat"),
      Sampler.foldOffset(prim.uv[2],"mirroredrepeat")),
    "CPU origin removal preserves repeat and mirror sampling phase")
  prim.callbackOffset=123
  local callbackRows,callbackU,callbackV=Renderer.meshRows(prim)
  check(callbackU==0 and callbackV==0 and near(callbackRows[1][4],prim.uv[1]),
    "callback texture scaling retains source coordinates")
end
check(Renderer.shouldBoundTextureUV({boundedTextureUV=true}) == true,
  "mobile UV protection can be forced on")
check(Renderer.shouldBoundTextureUV({boundedTextureUV=false}) == false,
  "desktop/reference path can be forced unchanged")
do
  local oldLove = love
  love = {graphics={getRendererInfo=function() return "OpenGL ES","3.2","Qualcomm","Adreno" end}}
  check(Renderer.isAndroidGraphics() == true,
    "GLES renderer selects the Android compatibility path")
  check(Renderer.shouldBoundTextureUV({}) == true,
    "mobile GLES automatically enables bounded UV sampling")
  check(Renderer.shouldReceiveModelSunShadows({}) == false,
    "mobile GLES disables unstable packed model self-shadow reception")
  local source,tier=Renderer.activeShaderSource({})
  check(source==Renderer.MOBILE_SHADER_SOURCE and tier=="mobile-simple",
    "Android automatically selects the simple Stadium shader")
  love = oldLove
end
do
  local oldLove=love
  love={graphics={getRendererInfo=function() return "Metal","3.1","Apple","GPU" end}}
  local source,tier=Renderer.activeShaderSource({})
  check(Renderer.isMobileGraphics() and not Renderer.isAndroidGraphics(),
    "Metal keeps mobile depth safeguards without impersonating Android")
  check(source==Renderer.SHADER_SOURCE and tier=="lit",
    "desktop Metal retains the full Stadium and Manga shader")
  love=oldLove
end
do
  local oldLove=love
  love={graphics={getRendererInfo=function() return "OpenGL","4.6","NVIDIA","GPU" end}}
  local source,tier=Renderer.activeShaderSource({})
  check(source==Renderer.SHADER_SOURCE and tier=="lit",
    "desktop OpenGL retains the full Stadium and Manga shader")
  check(Renderer.activeShaderSource({simpleMobileShader=true})==Renderer.MOBILE_SHADER_SOURCE,
    "simple shader can be forced for compatibility diagnostics")
  love=oldLove
end
check(Renderer.shouldReceiveModelSunShadows({modelSunShadows=true})==true,
  "model self-shadows remain explicitly selectable for diagnostics")

local shader = assert(Renderer.SHADER_SOURCE)
local foldAt = assert(shader:find("uv = foldTextureUV%(uv, wrapMode%);"))
local multiplyAt = assert(shader:find("vec2 p = uv %* size %- vec2%(0%.5%);"))
check(foldAt < multiplyAt, "UV is folded before texel-space multiplication")
check(shader:find("uniform float boundedUVEnabled;", 1, true) ~= nil,
  "bounded UV path is runtime-selectable")
check(shader:find("uniform vec2 primaryWrapMode;", 1, true) ~= nil,
  "primary wrap mode reaches shader")
check(shader:find("uniform vec2 secondaryWrapMode;", 1, true) ~= nil,
  "secondary wrap mode reaches shader")
check(shader:find("primarySize, primaryWrapMode", 1, true) ~= nil,
  "primary 3-point sample uses bounded wrap mode")
check(shader:find("secondaryWrapMode", 1, true) ~= nil,
  "secondary 3-point sample uses bounded wrap mode")
check(Renderer.shaderSource(true):find("#define STADIUM_FLOAT mediump",1,true)~=nil,
  "test shader can force the GLES2 minimum precision path")
check(shader:find("clip.z-=decalDepthBias*clip.w",1,true)~=nil,
  "coplanar detail layers have a clip-space depth stabilization path")
local mobileShader=assert(Renderer.MOBILE_SHADER_SOURCE)
check(mobileShader:find("stadiumShade=clamp",1,true)~=nil,
  "Android shader retains v0.10.7 Stadium lighting")
check(mobileShader:find("paperNoise",1,true)==nil
    and mobileShader:find("sample3",1,true)==nil
    and mobileShader:find("sunMap",1,true)==nil,
  "Android shader omits procedural Manga, manual filtering and model shadow sampling")
check(mobileShader:find("VaryingTexCoord.st",1,true)~=nil,
  "Android simple shader retains precision-safe LOVE texture coordinates")

print(("RESULT checks=%d failures=%d"):format(checks, failures))
if failures > 0 then os.exit(1) end
