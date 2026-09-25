-- Dump the colour inputs a move's battle FX feed to the renderer, without a
-- GPU. Run from the Gen1Recomp root:
--   luajit mods/STADIUM2_IMPORTER/tools/dump_fx_colors.lua [move] [> out.txt]
-- STADIUM2_ROM overrides the ROM path. Prints emitter materials and colour
-- tracks (including mode-8 screen colour layers) and, for each shape drawn,
-- every primitive's combiner, render mode, controller colour track and
-- texture formats with their average intensity and alpha.
package.path="./?.lua;./?/init.lua;"..package.path
local prefix="mods.STADIUM2_IMPORTER.lib."
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Resources=require(prefix.."stadium2_battle_fx_resources")
local Renderer=require(prefix.."renderer")

local moveId=tonumber(arg and arg[1]) or 201
local path=os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file=assert(io.open(path,"rb"));local rom=file:read("*a");file:close()
local catalog=assert(FxRom.catalog(rom))
local move=assert(catalog.moves[moveId],"move out of range")

local function show(value,depth,seen)
  depth=depth or 0;seen=seen or {}
  if type(value)~="table" then return tostring(value) end
  if seen[value] then return "<cycle>" end
  if depth>4 then return "{...}" end
  seen[value]=true
  local keys={}
  for k in pairs(value) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  local parts={}
  for _,k in ipairs(keys) do
    local v=value[k]
    if type(v)~="function" and k~="raw" then
      parts[#parts+1]=tostring(k).."="..show(v,depth+1,seen)
    end
  end
  seen[value]=nil
  return "{"..table.concat(parts,", ").."}"
end

local function section(title,fn)
  print(("== %s"):format(title))
  local ok,err=pcall(fn)
  if not ok then print("  ERROR: "..tostring(err)) end
end

local shapes={}
section(("move %d emitters"):format(moveId),function()
  for _,bank in ipairs({"primaryDispatch","alternateDispatch"}) do
    for _,route in ipairs(move[bank] or {}) do
      if route.programId then
        local program=catalog.programs[route.programId]
        for index,record in ipairs(program and program.records or {}) do
          local event=record.emitter
          if event then
            local material=event.material or {}
            local shape=tonumber(material.shapeId)
            if shape then shapes[shape]=true end
            print(("-- %s program %d record %d opcode %s mode %s kind %s shape %s")
              :format(bank,route.programId,index,tostring(record.opcode),
                tostring(event.mode),tostring(event.descriptorKind),tostring(shape)))
            print("   material "..show({primaryColor=material.primaryColor,
              secondaryColor=material.secondaryColor,constantColor=material.constantColor,
              nativePrimaryTrack=material.nativePrimaryTrack,
              nativeSecondaryTrack=material.nativeSecondaryTrack,
              nativeAlphaInitial=material.nativeAlphaInitial,
              nativeAlphaBaseRamp=material.nativeAlphaBaseRamp,
              nativeAlphaRamp=material.nativeAlphaRamp,
              nativeConstantColors=material.nativeConstantColors}))
            if event.nativeColorTrack then
              print("   screen colour track (mode 8, shape 90) "..show(event.nativeColorTrack))
              shapes[90]=true
            end
            if event.nativeModelColor then
              print("   model colour "..show(event.nativeModelColor))
            end
          end
        end
      end
    end
  end
end)

local function textureStats(texture)
  local rgba=texture and texture.rgba
  if type(rgba)~="string" or #rgba<4 then return "no pixels" end
  local n,sumI,sumA,dark=0,0,0,0
  for i=1,#rgba-3,4 do
    local r,g,b,a=rgba:byte(i,i+3)
    local l=(r+g+b)/3
    sumI=sumI+l;sumA=sumA+a;n=n+1
    if l<32 and a>128 then dark=dark+1 end
  end
  return ("%dx%d fmt=%s siz=%s meanI=%.1f meanA=%.1f darkOpaque=%.1f%%"):format(
    texture.w or 0,texture.h or 0,tostring(texture.format),tostring(texture.size),
    sumI/n,sumA/n,100*dark/n)
end

local resolved
section("resources",function()
  resolved=assert(Resources.resolve(rom:sub(Resources.ROM_START+1,Resources.ROM_END),
    move.resources))
  print("   resolved")
end)

local ids={}
for id in pairs(shapes) do ids[#ids+1]=id end
table.sort(ids)
for _,shapeId in ipairs(ids) do
  section(("shape %d"):format(shapeId),function()
    local shape=assert(Resources.shapeFromResolved(resolved,shapeId))
    local model=assert(Resources.modelFromShape(shape,"dump-shape-"..shapeId))
    print(("   geometryMode=%s compiledLayout=%s staticPose=%s battleFx=%s smoothSampled=%s")
      :format(tostring(model.battleFxGeometryMode),tostring(model.battleFxCompiledLayout),
        tostring(model.staticPose),tostring(model.battleFx),
        tostring(Renderer.smoothSampled(model))))
    for index,texture in ipairs(model.textures or {}) do
      print(("   texture %d %s ptr=%s"):format(index,textureStats(texture),
        tostring(texture.sourcePointer)))
    end
    for index,prim in ipairs(model.prims or {}) do
      local material=prim.material or {}
      print(("   prim %d tex=%s renderState=%s nodeLayer=%s lighting=%s")
        :format(index,tostring(prim.tex),tostring(prim.battleFxRenderState),
          tostring(prim.battleFxNodeLayer),tostring(prim.lighting)))
      print("     material "..show({phase5=material.phase5,combiner=material.combiner,
        primitiveColor=material.primitiveColor,environmentColor=material.environmentColor,
        primitiveLodFraction=material.primitiveLodFraction,
        displayListState=material.displayListState}))
      local controller=prim.battleFxController
      if controller then
        local cc=controller.colorController
        print("     colour track "..show(cc and cc.colorTrack))
        for _,item in ipairs(controller.items or {}) do
          print(("     item unit=%s ptr=%s %sx%s sampler=%s texPtrs=%s scroll=%s"):format(
            tostring(item.textureUnit),tostring(item.texturePointer),
            tostring(item.textureWidth),tostring(item.textureHeight),show(item.sampler),
            show(item.controller and item.controller.texturePointers),
            show(item.controller and item.controller.tileScroll)))
        end
      end
      local lit=Renderer.surfaceLit({lightingEnabled=prim.lighting~=false},model,material)
      print("     surfaceLit(static material)="..tostring(lit))
    end
  end)
end
