package.path = "./?.lua;./?/init.lua;" .. package.path

local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
local Sampler=require("mods.STADIUM2_IMPORTER.lib.sampler")
local directory=arg[1] or
  "/home/deftones/.local/share/love/pokemon-love2d/crystal_251/stadium2/normal"
local rows={}
local totals={models=0,prims=0,over8=0,over16=0,over32=0,over64=0,
  texel256=0,texel512=0,texel1024=0,decals=0,decalModels=0}

for dex=1,251 do
  local path=("%s/%03d.dsm"):format(directory,dex)
  local file=io.open(path,"rb")
  if file then
    local bytes=file:read("*a");file:close()
    local model=Pack.parse(bytes)
    if model then
      totals.models=totals.models+1
      local hasDecal=false
      for index,prim in ipairs(model.prims or {}) do
        totals.prims=totals.prims+1
        if prim.decal then totals.decals=totals.decals+1;hasDecal=true end
        local us,vs=Sampler.uvScale(prim.sampler,prim.textureScale)
        local maximum=0
        local minU,maxU,minV,maxV=math.huge,-math.huge,math.huge,-math.huge
        for i=1,#(prim.uv or {}),2 do
          local u,v=(prim.uv[i] or 0)*us,(prim.uv[i+1] or 0)*vs
          maximum=math.max(maximum,math.abs(u),math.abs(v))
          minU,maxU=math.min(minU,u),math.max(maxU,u)
          minV,maxV=math.min(minV,v),math.max(maxV,v)
        end
        if minU==math.huge then minU,maxU,minV,maxV=0,0,0,0 end
        for _,limit in ipairs({8,16,32,64}) do
          if maximum>limit then totals["over"..limit]=totals["over"..limit]+1 end
        end
        local texture=model.textures and model.textures[prim.tex]
        local texelMaximum=maximum*math.max(texture and texture.w or 1,
          texture and texture.h or 1)
        if texelMaximum>256 then totals.texel256=totals.texel256+1 end
        if texelMaximum>512 then totals.texel512=totals.texel512+1 end
        if texelMaximum>1024 then totals.texel1024=totals.texel1024+1 end
        rows[#rows+1]={maximum=maximum,texelMaximum=texelMaximum,dex=dex,index=index,
          texture=prim.tex,width=texture and texture.w,height=texture and texture.h,
          vertices=prim.nverts,decal=prim.decal==true,
          minU=minU,maxU=maxU,minV=minV,maxV=maxV,
          span=math.max(maxU-minU,maxV-minV)}
      end
      if hasDecal then totals.decalModels=totals.decalModels+1 end
    end
  end
end

table.sort(rows,function(a,b)return a.maximum>b.maximum end)
print(("models=%d prims=%d decals=%d decalModels=%d uv>8=%d uv>16=%d uv>32=%d uv>64=%d texel>256=%d texel>512=%d texel>1024=%d")
  :format(totals.models,totals.prims,totals.decals,totals.decalModels,totals.over8,totals.over16,
    totals.over32,totals.over64,totals.texel256,totals.texel512,totals.texel1024))
for i=1,math.min(30,#rows) do
  local row=rows[i]
  print(("dex=%03d prim=%d maxUV=%.6f span=%.6f u=[%.3f,%.3f] v=[%.3f,%.3f] maxTexel=%.2f tex=%s %sx%s verts=%s decal=%s")
    :format(row.dex,row.index,row.maximum,row.span,row.minU,row.maxU,row.minV,row.maxV,
      row.texelMaximum,tostring(row.texture),
      tostring(row.width),tostring(row.height),tostring(row.vertices),tostring(row.decal)))
end
