-- Renderer-neutral packets built from persistent battle-FX snapshots.
local Attachment=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")
local Packets={}
local function copy(v,s)if type(v)~="table"then return v end;s=s or{};if s[v]then return s[v]end;local o={};s[v]=o;for k,x in pairs(v)do o[copy(k,s)]=copy(x,s)end;return o end
local function vec(v,d)if type(v)~="table"then return{d,d,d}end;return{tonumber(v[1]or v.x)or d,tonumber(v[2]or v.y)or d,tonumber(v[3]or v.z)or d}end
local function mul(a,b)return{a[1]*b[1],a[2]*b[2],a[3]*b[3]}end
-- func_841028DC copies the three authored halfword angles to the visual
-- object's transform. Use the same Z/Y/X basis as Stadium model bones.
local function matrix(p,s,r)
  r=vec(r,0)
  local x,y,z=r[1]*math.pi/32768,r[2]*math.pi/32768,r[3]*math.pi/32768
  local sx,cx,sy,cy,sz,cz=math.sin(x),math.cos(x),math.sin(y),math.cos(y),math.sin(z),math.cos(z)
  return{cy*cz*s[1],(sx*sy*cz-cx*sz)*s[2],(cx*sy*cz+sx*sz)*s[3],p[1],
    cy*sz*s[1],(sx*sy*sz+cx*cz)*s[2],(cx*sy*sz-sx*cz)*s[3],p[2],
    -sy*s[1],sx*cy*s[2],cx*cy*s[3],p[3],0,0,0,1}
end
local function diagnostic(p,code,message)return{code=code,severity="warning",effectId=p.effectId,programId=p.event and p.event.programId,address=p.event and p.event.address,kind="draw-packet",message=message}end

function Packets.build(snapshot,options)
  snapshot=type(snapshot)=="table"and snapshot or{};options=type(options)=="table"and options or{}
  local out={frame=snapshot.frame or 0,packets={},diagnostics={}}
  for _,particle in ipairs(snapshot.particles or{})do
    local context={effectId=particle.effectId,programId=particle.event and particle.event.programId,address=particle.event and particle.event.address,particle=copy(particle)}
    if type(options.contextForParticle)=="function"then
      local ok,value=pcall(options.contextForParticle,copy(particle),copy(snapshot),copy(options.context))
      if ok and type(value)=="table"then for k,v in pairs(value)do context[k]=v end
      else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-context",ok and"particle context unavailable"or tostring(value))end
    elseif type(options.context)=="table"then for k,v in pairs(options.context)do context[k]=v end end
    local contract=particle.attachment or(particle.event and particle.event.attachment)
    local resolved
    if type(options.resolvePlacement)=="function"then
      local ok,value=pcall(options.resolvePlacement,copy(contract),copy(context),copy(particle))
      if ok then resolved=value else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-placement",tostring(value))end
    elseif contract then resolved=Attachment.resolve(contract,context)end
    if type(resolved)=="table"and resolved.resolved then
      local material=particle.material or{};local shape=material.selectedShapeId or material.primaryShapeId or material.shapeId or particle.shapeId
      if tonumber(shape)and tonumber(shape)>0 then
        local ps=vec(particle.scale,1);local as=tonumber(resolved.scale)and{resolved.scale,resolved.scale,resolved.scale}or vec(resolved.scale,1);local scale=mul(ps,as);local position=vec(resolved.position,0)
        out.packets[#out.packets+1]={kind="common-particle",particleId=particle.id,effectId=particle.effectId,programId=particle.event and particle.event.programId,shapeId=shape,age=particle.age,frame=particle.frame,position=position,scale=scale,rotation=copy(particle.rotation),matrix=matrix(position,scale,particle.rotation),material=copy(material),attachment=copy(resolved)}
      else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-shape","particle has no resolved primary shape")end
    elseif type(resolved)=="table"and resolved.diagnostic then out.diagnostics[#out.diagnostics+1]=copy(resolved.diagnostic)
    else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-placement","particle placement is unresolved")end
  end
  return out
end
return Packets
