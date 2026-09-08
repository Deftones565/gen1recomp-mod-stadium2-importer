package.path = "./?.lua;./?/init.lua;" .. package.path

local prefix="mods.STADIUM2_IMPORTER.lib."
local parseCount,releaseCount=0,0
package.loaded[prefix.."rom"]={}
package.loaded[prefix.."extract"]={configure=function() end}
package.loaded[prefix.."cache"]={
  bind=function() end, read=function(species,variant)
    return ("%d:%s"):format(species,variant)
  end, readSpecial=function(name) return "special:"..name end,
}
package.loaded[prefix.."discovery"]={bind=function() end}
package.loaded[prefix.."palette"]={}
package.loaded[prefix.."model_handlers"]={}
package.loaded[prefix.."pack"]={
  parse=function(bytes)
    parseCount=parseCount+1
    return {bytes=bytes,prims={},anims={},instance=parseCount}
  end,
  release=function(model)
    releaseCount=releaseCount+1
    model.released=true
  end,
}
package.loaded[prefix.."renderer"]={new=function(model,options)
  return {model=model,options=options}
end}
package.loaded[prefix.."importer"]=nil

local Importer=require(prefix.."importer")
local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local first=assert(Importer.createModel(25,"shiny"))
local second=assert(Importer.createModel(25,"shiny"))
ok(first~=second and first.instance~=second.instance,
  "owned model creation returns independent instances")
ok(first.variant=="shiny" and first.bytes=="25:shiny",
  "owned model retains requested variant and pack")
first.prims[1]={custom=true}
ok(second.prims[1]==nil,"owned model mutation is isolated")

local renderer=assert(Importer.newRendererFromModel(first,{textureFilter="linear"}))
ok(renderer.model==first and renderer.options.textureFilter=="linear",
  "renderer accepts caller-owned model and options")
ok(type(renderer.options.shaderStyleProvider)=="function",
  "caller-owned renderer receives live shader-style provider")
ok(Importer.releaseModel(first) and first.released and releaseCount==1,
  "owned model release delegates resource cleanup")
ok(not Importer.releaseModel(first) and releaseCount==1,
  "owned model cannot be released twice")
local borrowed=assert(Importer.loadModel(26,"normal"))
ok(not Importer.releaseModel(borrowed),"borrowed model release is rejected")

local parsed=assert(Importer.parsePack("external"))
ok(Importer.releaseModel(parsed),"parsed packs receive caller ownership")
local special=assert(Importer.createSpecialModel("unown_b"))
ok(special.bytes=="special:unown_b" and Importer.releaseModel(special),
  "special packs receive independent caller ownership")

local bad,err=Importer.createModel(0,"normal")
ok(bad==nil and err=="species out of range","owned model validates species")

print(("%d checks passed (Stadium 2 public model API)"):format(checks))
