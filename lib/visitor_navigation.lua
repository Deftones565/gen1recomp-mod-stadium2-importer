-- Conservative scenery occupancy, built once beside the cached mesh. Four-unit
-- cells include complete triangle bounds; false positives stop visitors safely.
local N={maps={}}
local floor,min,max=math.floor,math.min,math.max
function N.build(id,rows)
 require("mods.STADIUM2_IMPORTER.lib.weather_surface").build(id,rows)
 local cells={}
 for i=1,#rows,3 do
  local a,b,c=rows[i],rows[i+1],rows[i+2]
  local loY,hiY=min(a[2],b[2],c[2]),max(a[2],b[2],c[2])
  -- Flat ground is support, not an obstacle. Restrict navigation to the
  -- authored play space; distant ground aprons never need collision storage.
  if hiY>.4 then
   local x0,x1=max(-200,min(a[1],b[1],c[1])),min(200,max(a[1],b[1],c[1]))
   local z0,z1=max(-200,min(a[3],b[3],c[3])),min(200,max(a[3],b[3],c[3]))
   for x=floor(x0/4),floor(x1/4) do
    local column=cells[x];if not column then column={};cells[x]=column end
    for z=floor(z0/4),floor(z1/4) do
     local stack=column[z];if not stack then stack={};column[z]=stack end
     for y=floor(max(.4,loY)/4),floor(min(120,hiY)/4) do stack[y]=true end
    end
   end
  end
 end
 N.maps[id]={cells=cells}
 return N.maps[id]
end
function N.clear(id) N.maps[id]=nil;require("mods.STADIUM2_IMPORTER.lib.weather_surface").maps[id]=nil end
function N.free(map,x,y,z,radius,height)
 if not map then return false end
 -- Stay inside supported land/cavern space; lake visitors are airborne.
 if math.abs(x)>190 or math.abs(z)>190 or y<0 then return false end
 for xx=floor((x-radius)/4),floor((x+radius)/4) do
  local column=map.cells[xx]
  if column then for zz=floor((z-radius)/4),floor((z+radius)/4) do
   local stack=column[zz]
   if stack then for yy=floor(y/4),floor((y+height)/4) do if stack[yy] then return false end end end
  end end
 end
 return true
end
function N.sweep(map,x,y,z,tx,ty,tz,radius,height)
 local distance=math.sqrt((tx-x)^2+(ty-y)^2+(tz-z)^2)
 local steps=math.max(1,math.ceil(distance/2))
 for i=0,steps do
  local t=i/steps
  if not N.free(map,x+(tx-x)*t,y+(ty-y)*t,z+(tz-z)*t,radius,height) then return false end
 end
 return true
end
return N
