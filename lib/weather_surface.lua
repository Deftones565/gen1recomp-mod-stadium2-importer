-- Four-unit sampled top surfaces, rasterized once with scenery construction.
-- Stores heights only; rain never scans the scenery triangles at runtime.
local S={maps={}}
function S.build(id,rows)
 local heights={}
 for i=1,#rows,3 do
  local a,b,c=rows[i],rows[i+1],rows[i+2]
  local det=(b[3]-c[3])*(a[1]-c[1])+(c[1]-b[1])*(a[3]-c[3])
  if math.abs(det)>1e-8 then
   local x0=math.max(-44,math.ceil(math.min(a[1],b[1],c[1])/4))
   local x1=math.min(44,math.floor(math.max(a[1],b[1],c[1])/4))
   local z0=math.max(-44,math.ceil(math.min(a[3],b[3],c[3])/4))
   local z1=math.min(44,math.floor(math.max(a[3],b[3],c[3])/4))
   for x=x0,x1 do for z=z0,z1 do
    local u=((b[3]-c[3])*(x*4-c[1])+(c[1]-b[1])*(z*4-c[3]))/det
    local v=((c[3]-a[3])*(x*4-c[1])+(a[1]-c[1])*(z*4-c[3]))/det
    if u>=-.00001 and v>=-.00001 and u+v<=1.00001 then
     local y=u*a[2]+v*b[2]+(1-u-v)*c[2];local key=(x+44)*89+z+44
     heights[key]=math.max(heights[key] or -math.huge,y)
    end
   end end
  end
 end
 S.maps[id]=heights
end
function S.height(id,x,z)
 local map=S.maps[id];if not map then return -.12 end
 local ix,iz=math.floor(x/4+.5),math.floor(z/4+.5)
 if math.abs(ix)>44 or math.abs(iz)>44 then return -.12 end
 return map[(ix+44)*89+iz+44] or ((id=='freshwater' or id=='ocean') and -.95 or -.12)
end
return S
