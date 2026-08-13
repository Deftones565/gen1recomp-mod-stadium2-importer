local function scriptRoot()
  local path=(arg and arg[0]) or ""
  path=path:gsub("\\","/")
  local root=path:match("^(.*)/tests/[^/]+$")
  if root and root~="" then return root end
  return "mods/STADIUM2_IMPORTER"
end

local function read(path)
  local f=assert(io.open(path,"rb"))
  local s=f:read("*a")
  f:close()
  return s
end

local root=scriptRoot()
local aa=read(root.."/lib/battle_aa.lua")
local scene=read(root.."/lib/battle_scene.lua")
local renderer=read(root.."/lib/renderer.lua")
local checks,failures=0,0

local function check(name,condition,actual,expected)
  checks=checks+1
  if condition then
    io.write(("[watercolor-smallres] PASS %s\n"):format(name))
  else
    failures=failures+1
    io.write(("[watercolor-smallres] FAIL %s actual=%s expected=%s\n")
      :format(name,tostring(actual),tostring(expected)))
  end
end

local function contains(s,needle)
  return s:find(needle,1,true)~=nil
end

local function near(a,b)
  return math.abs(a-b)<1e-9
end

local function scaleFor(height)
  return math.max(1,1080/math.max(1,height))
end

check("battle AA original expand signature",contains(aa,"function AA.expand(width,height)"),nil,true)
check("battle AA has no watercolor supersampling",not contains(aa,"watercolorFactor"),nil,true)
check("battle AA has no minimum render factor",not contains(aa,"minimumFactor"),nil,true)
check("battle scene uses original AA expansion",contains(scene,"AA.expand(pixelWidth,pixelHeight)"),nil,true)
check("battle scene has no watercolor canvas scaling",not contains(scene,"watercolorRenderFactor"),nil,true)
check("shader uses current canvas dimensions",contains(renderer,"love_ScreenSize.y"),nil,true)
check("shader reference height is 1080",contains(renderer,"1080.0/max(1.0,love_ScreenSize.y)"),nil,true)
check("shader has exact high-resolution gate",contains(renderer,"if(watercolorScreenScale<=1.0001){"),nil,true)
check("small-resolution path uses virtual coordinates",contains(renderer,"vec2 watercolorCoords=screen_coords.xy*watercolorScreenScale;"),nil,true)

local legacy=[=[float paperNoise=fract(sin(dot(floor(screen_coords.xy*0.5),
      vec2(12.9898,78.233)))*43758.5453)-0.5;
    float broadWash=sin(screen_coords.x*0.021+screen_coords.y*0.017)*0.5
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
    shaded=mix(shaded,watercolor,mangaAmount);]=]
check("1080p-plus branch retains legacy watercolor math",contains(renderer,legacy),nil,true)

check("1080p scale unchanged",near(scaleFor(1080),1),scaleFor(1080),1)
check("1440p scale unchanged",near(scaleFor(1440),1),scaleFor(1440),1)
check("2160p scale unchanged",near(scaleFor(2160),1),scaleFor(2160),1)
check("800p virtual density",near(scaleFor(800),1.35),scaleFor(800),1.35)
check("720p virtual density",near(scaleFor(720),1.5),scaleFor(720),1.5)
check("540p virtual density",near(scaleFor(540),2),scaleFor(540),2)
check("800p virtual height",near(800*scaleFor(800),1080),800*scaleFor(800),1080)
check("720p virtual height",near(720*scaleFor(720),1080),720*scaleFor(720),1080)

io.write(("[watercolor-smallres] RESULT checks=%d failures=%d\n"):format(checks,failures))
os.exit(failures==0 and 0 or 1)
