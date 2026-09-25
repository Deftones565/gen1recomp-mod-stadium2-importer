package.path="./?.lua;./?/init.lua;"..package.path
local P=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_draw_packets")
local n=0;local function ok(v,m)n=n+1;if not v then error("FAIL "..m,0)end end
local particle={id=4,effectId=2,age=3,shapeId=47,scale={2,3,4},event={programId=259,address=0x8417B624},attachment={flags=0x180,flags2=0},material={primaryShapeId=47,selectedShapeId=95,primaryColor={1,2,3,4}}}
local source={frame=8,particles={particle}}
local built=P.build(source,{resolvePlacement=function(contract,context,p)return{resolved=true,position={10,20,30},scale=.5}end})
ok(#built.packets==1 and built.frame==8,"one persistent particle packet")
local q=built.packets[1];ok(q.shapeId==95 and q.particleId==4 and q.programId==259,"selected shape and identity")
ok(q.scale[1]==1 and q.scale[2]==1.5 and q.scale[3]==2,"particle and attachment scales compose")
ok(q.matrix[1]==1 and q.matrix[4]==10 and q.matrix[8]==20 and q.matrix[12]==30,"matrix translation and scale")
q.material.primaryColor[1]=99;ok(particle.material.primaryColor[1]==1,"packet is detached")
local skipped=P.build(source,{resolvePlacement=function()return{resolved=false,diagnostic={code="unresolved",severity="warning",effectId=2,programId=259,address=1,kind="attachment",message="no anchor"}}end})
ok(#skipped.packets==0 and skipped.diagnostics[1].code=="unresolved","unresolved placement does not invent draw")
local noShape=P.build({particles={{id=1,effectId=1,scale={1,1,1},event={}}}},{resolvePlacement=function()return{resolved=true,position={0,0,0},scale=1}end})
ok(noShape.diagnostics[1].code=="draw-shape","missing shape is explicit")
local exploded=P.build(source,{contextForParticle=function()error("boom")end})
ok(exploded.diagnostics[1].code=="draw-context","context errors are diagnostics")
P.build(source,{contextNeedsSnapshot=false,contextForParticle=function(p,s,c)
  ok(s==nil and c==nil,"placement adapter can skip unused scene/snapshot copies")
  p.id=999
  return {}
end})
ok(particle.id==4,"fast placement still isolates the public particle")
P.build(source,{context={value=7},contextForParticle=function(p,s,c)
  ok(s.frame==8 and c.value==7,"default callback retains complete context")
  s.particles[1].id=999
  return {}
end})
ok(particle.id==4,"default callback cannot mutate persistent particles")
particle.rotation={0,0,0x4000}
local rotated=P.build(source,{resolvePlacement=function()return{resolved=true,position={10,20,30},scale=1}end}).packets[1]
ok(math.abs(rotated.matrix[1])<1e-12 and rotated.matrix[2]==-3
  and rotated.matrix[5]==2 and rotated.matrix[12]==30,
  "native quarter-turn rotation reaches the draw matrix without rotating its anchor")
print(("%d checks passed (Stadium 2 battle FX draw packets)"):format(n))
