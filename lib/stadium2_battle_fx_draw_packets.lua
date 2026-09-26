-- Renderer-neutral packets built from persistent battle-FX snapshots.
local Attachment=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")
local single=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local ModelAnimation=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_model_animation")
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
-- 84102B3C selects the direct-shape transform from the shape geometry mode
-- (jump table 84188BD4). All world modes use the scalar at object +0x18,
-- position +0x20..+0x28 and the halfword angles at +0x6A..+0x6E, with angle
-- index (u16 angle) >> 4 into the ROM sin (D_80087E50) / cos (D_80088E50)
-- tables. Native matrices are row-vector; rows are written here as the
-- renderer's column-vector basis columns.
local function nativeTrig(tables,angle)
  local index=math.floor((tonumber(angle) or 0)%65536/16)
  local sin=tables and tables.tableA and tables.tableA[index+1]
  local cos=tables and tables.tableB and tables.tableB[index+1]
  return sin,cos
end
local function normalized(v)
  local length=math.sqrt(v[1]*v[1]+v[2]*v[2]+v[3]*v[3])
  if length==0 or length~=length then return nil end
  return{v[1]/length,v[2]/length,v[3]/length}
end
local function cross(a,b)return{a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]}end
-- Camera matrix +0x64 is the look-at built from eye/focus/up (+0xA8/+0xB4/
-- +0xC0). Its first three columns are the camera right, up and eye-minus-
-- focus axes, which the billboard builders copy as object rows.
local function cameraAxes(camera)
  local eye,focus=camera and camera.eye,camera and camera.focus
  if type(eye)~="table" or type(focus)~="table" then return nil end
  local back=normalized({eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]})
  if not back then return nil end
  local right=normalized(cross(vec(camera.up or {0,1,0},0),back))
  if not right then return nil end
  return right,cross(back,right),back
end
local function scaledRow(row,s)return{single(row[1]*s),single(row[2]*s),single(row[3]*s)}end
local function columns(x,y,z,p,worldScale)
  local w=vec(worldScale,1)
  return{x[1]*w[1],y[1]*w[2],z[1]*w[3],p[1],
    x[2]*w[1],y[2]*w[2],z[2]*w[3],p[2],
    x[3]*w[1],y[3]*w[2],z[3]*w[3],p[3],0,0,0,1}
end

-- Returns the direct-shape matrix for geometry modes 0..4, or nil plus a
-- diagnostic code/message when a native input is unavailable.
function Packets.shapeMatrix(transform,geometryMode,options)
  options=type(options)=="table" and options or {}
  if type(transform)~="table" then return nil,"draw-native-transform","particle has no native transform inputs" end
  geometryMode=tonumber(geometryMode)
  local s=tonumber(transform.nativeScale) or 1
  local r=vec(transform.rotation,0)
  local p=vec(transform.position,0)
  local tables=options.trigTables
  if geometryMode==0 or geometryMode==2 then
    -- 84103A3C (mode 0) and 84103BCC (mode 2): Y, X, Z angle composition.
    -- Mode 0 scales every row; mode 2 scales only the second row.
    local sx,cx=nativeTrig(tables,r[1])
    local sy,cy=nativeTrig(tables,r[2])
    local sz,cz=nativeTrig(tables,r[3])
    if not (sx and cx and sy and cy and sz and cz) then
      return nil,"unresolved-shape-trig","shape transform requires ROM angle tables"
    end
    local x={single(cy*cz+sx*sy*sz),single(cx*sz),single(-sy*cz+sx*cy*sz)}
    local y={single(-cy*sz+sx*sy*cz),single(cx*cz),single(sy*sz+sx*cy*cz)}
    local z={single(cx*sy),single(-sx),single(cx*cy)}
    local xs=geometryMode==0 and s or 1
    return columns(scaledRow(x,xs),scaledRow(y,s),scaledRow(z,xs),p,transform.worldScale)
  elseif geometryMode==1 or geometryMode==3 or geometryMode==4 then
    local right,up,back=cameraAxes(options.camera)
    if not right then
      return nil,"unresolved-billboard-camera","billboard transform requires camera eye and focus"
    end
    local x,y=right,up
    if geometryMode~=1 then
      -- 84104590 (mode 4) / 84104668 (mode 3) rotate the camera axes by the
      -- +0x6E angle before scaling.
      local sn,cs=nativeTrig(tables,r[3])
      if not (sn and cs) then
        return nil,"unresolved-shape-trig","shape transform requires ROM angle tables"
      end
      x={right[1]*cs+up[1]*sn,right[2]*cs+up[2]*sn,right[3]*cs+up[3]*sn}
      y={-right[1]*sn+up[1]*cs,-right[2]*sn+up[2]*cs,-right[3]*sn+up[3]*cs}
    end
    -- 84104528 (mode 1) and 84104590 (mode 4) scale every row; 84104668
    -- (mode 3) scales only the second row.
    local xs=geometryMode==3 and 1 or s
    return columns(scaledRow(x,xs),scaledRow(y,s),scaledRow(back,xs),p,transform.worldScale)
  end
  return nil,"unsupported-shape-geometry-mode",
    ("shape geometry mode %s has no world transform"):format(tostring(geometryMode))
end

local function diagnostic(p,code,message)return{code=code,severity="warning",effectId=p.effectId,programId=p.event and p.event.programId,address=p.event and p.event.address,kind="draw-packet",message=message}end
Packets.nativeMatrix=matrix

function Packets.build(snapshot,options)
  snapshot=type(snapshot)=="table"and snapshot or{};options=type(options)=="table"and options or{}
  local out={frame=snapshot.frame or 0,packets={},screenPackets={},diagnostics={}}
  for _,particle in ipairs(snapshot.particles or{})do
    if not particle.nativeHidden then
    if particle.event and particle.event.mode==7 then
      local material=particle.material or {}
      local shape=material.selectedShapeId or material.primaryShapeId or material.shapeId or particle.shapeId
      if tonumber(shape) and tonumber(shape)>0 then
        local function coord(value)
          value=value<0 and math.ceil(value) or math.floor(value)
          value=value%65536;return value>=32768 and value-65536 or value
        end
        local p=vec(particle.position,0)
        local s=single(vec(particle.scale,1)[1])
        local angle=math.floor((vec(particle.rotation,0)[3]%65536)/16)
        local tables=options.trigTables
        local sin=tables and tables.tableA[angle+1]
        local cos=tables and tables.tableB[angle+1]
        if sin==nil or cos==nil then
          out.diagnostics[#out.diagnostics+1]=diagnostic(particle,'unresolved-screen-trig','screen transform requires ROM angle tables')
        else
          -- 8410383C uses only Z rotation; its row-vector matrix is
          -- transposed here for the renderer's column-vector convention.
          local a,b=single(cos*s),single(sin*s)
          out.screenPackets[#out.screenPackets+1]={kind='screen-particle',
            particleId=particle.id,born=particle.born,effectId=particle.effectId,programId=particle.event.programId,
            shapeId=shape,age=particle.age,frame=particle.frame,materialFrame=particle.age,material=copy(material),
            matrix={a,b,0,coord(p[1]),-b,a,0,coord(p[2]),0,0,1,0,0,0,0,1},
            -- 841038F4 scales only the second model-space axis.
            matrixYScale={cos,b,0,coord(p[1]),-sin,a,0,coord(p[2]),0,0,1,0,0,0,0,1}}
        end
      else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,'draw-shape','screen particle has no resolved shape') end
    elseif not options.screenOnly then
    -- One private copy per particle serves the context, both callbacks and
    -- the packet (callbacks read it; the snapshot itself stays untouched).
    -- shareParticles: the caller's snapshot is its own read-only view and its
    -- callbacks only read, so the particle is used as is.
    local own=options.shareParticles and particle or copy(particle)
    local context={effectId=particle.effectId,programId=particle.event and particle.event.programId,address=particle.event and particle.event.address,particle=own}
    if type(options.contextForParticle)=="function"then
      local callbackSnapshot,callbackContext
      if options.contextNeedsSnapshot~=false then
        callbackSnapshot,callbackContext=copy(snapshot),copy(options.context)
      end
      local ok,value=pcall(options.contextForParticle,own,
        callbackSnapshot,callbackContext)
      if ok and type(value)=="table"then for k,v in pairs(value)do context[k]=v end
      else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-context",ok and"particle context unavailable"or tostring(value))end
    elseif type(options.context)=="table"then for k,v in pairs(options.context)do context[k]=v end end
    for _,item in ipairs(context.diagnostics or {}) do
      local row=diagnostic(particle,item.code,item.message)
      row.address=item.address or row.address
      out.diagnostics[#out.diagnostics+1]=row
    end
    local contract=own.attachment or(own.event and own.event.attachment)
    local resolved
    if type(options.resolvePlacement)=="function"then
      local ok,value=pcall(options.resolvePlacement,contract,context,own)
      if ok then resolved=value else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-placement",tostring(value))end
    elseif contract then resolved=Attachment.resolve(contract,context)end
    if type(resolved)=="table"and resolved.resolved then
      local material=own.material or{};local shape=material.selectedShapeId or material.primaryShapeId or material.shapeId or particle.shapeId
      if tonumber(shape)and tonumber(shape)>0 then
        local ps=vec(particle.scale,1);local as=tonumber(resolved.scale)and{resolved.scale,resolved.scale,resolved.scale}or vec(resolved.scale,1);local scale=mul(ps,as);local position=vec(resolved.position,0)
        out.packets[#out.packets+1]={kind="common-particle",particleId=particle.id,effectId=particle.effectId,programId=particle.event and particle.event.programId,shapeId=shape,age=particle.age,frame=particle.frame,materialFrame=particle.age,position=position,scale=scale,rotation=own.rotation,matrix=matrix(position,scale,particle.rotation),material=material,attachment=copy(resolved),
          -- Direct shapes are transformed by 84102B3C at draw time, once the
          -- loaded shape's geometry mode is known (Packets.shapeMatrix).
          nativeTransform={position=copy(position),nativeScale=ps[1],worldScale=copy(as),rotation=vec(particle.rotation,0)}}
        out.packets[#out.packets].modelAnimation=ModelAnimation.packet(particle,snapshot.frame)
      elseif tonumber(shape)==0 and material.nativeMaterialColors then
        -- Null shape is a non-drawing controller. Dynamic writes are selected
        -- separately by transform+10, never by material+0/+2.
      else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-shape","particle has no resolved primary shape")end
    elseif type(resolved)=="table"and resolved.diagnostic then out.diagnostics[#out.diagnostics+1]=copy(resolved.diagnostic)
    else out.diagnostics[#out.diagnostics+1]=diagnostic(particle,"draw-placement","particle placement is unresolved")end
    end
    end
  end
  return out
end
return Packets
