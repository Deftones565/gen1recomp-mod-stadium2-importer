-- Shared by the woodland mesh and its resident visitor.
local P={u=-30,d=49,size=21,variant=1,yaw=0,model='tree_detailed'}
function P.treePosition(u,d)
 local radius=math.sqrt(u*u+d*d)
 if radius<108 then u,d=u*108/radius,d*108/radius end
 return (u-d)*.70710678,(-u-d)*.70710678
end
local perch
function P.position()
 if not perch then
  -- Intersect the crown above the trunk. Use the actual converted triangles,
  -- so the feet rest on the tree even if its mesh or scale changes.
  local rows=require('mods.STADIUM2_IMPORTER.assets.kenney_nature.models')[P.model]
  local top=-math.huge
  for i=1,#rows,3 do
   local a,b,c=rows[i],rows[i+1],rows[i+2]
   local det=(b[3]-c[3])*(a[1]-c[1])+(c[1]-b[1])*(a[3]-c[3])
   if math.abs(det)>1e-10 then
    local u=((b[3]-c[3])*(-c[1])+(c[1]-b[1])*(-c[3]))/det
    local v=((c[3]-a[3])*(-c[1])+(a[1]-c[1])*(-c[3]))/det
    local w=1-u-v
    if u>=0 and v>=0 and w>=0 then top=math.max(top,u*a[2]+v*b[2]+w*c[2]) end
   end
  end
  assert(top>-math.huge,'Woodland visitor tree has no perch surface')
  local x,z=P.treePosition(P.u,P.d)
  perch={x,top*P.size,z}
 end
 return perch[1],perch[2],perch[3]
end
return P
