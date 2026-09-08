package.path="./?.lua;./?/init.lua;"..package.path
local Router=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_router")
local Attachment=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")
local n=0;local function ok(v,m)n=n+1;if not v then error("FAIL "..m,0) end end
local move={primaryDispatch={{kind="program",programId=7,nested={x=1}},{kind="lifecycle",lifecycleId=3}},alternateDispatch={{kind="program",programId=8}}}
local selected=assert(Router.resolve(move,false));ok(#selected==2 and selected[1].programId==7,"primary ordering")
ok(assert(Router.resolve(move,true))[1].programId==8,"alternate only")
selected[1].nested.x=9;ok(move.primaryDispatch[1].nested.x==1,"router deep copy")
ok(select(1,Router.resolve({},false))==nil,"missing route rejected")
ok(select(1,Router.resolve(move,nil))==nil,"implicit alternate rejected")

local ops=Attachment.operations(0x459F)
for _,name in ipairs({"placementPreparation","primaryVisualPolicy","zeroAnchorY","externalScaleOffsetY","anchorCallback","fixedInitialScale","zeroAnchor","laneScalar","secondaryVisualPolicy"}) do ok(ops[name],"low bit "..name) end
ok(not Attachment.operations(0).modelAndSavedOrigin,"unset operation remains false")

local sum=assert(Attachment.sum({1,2,3},{10,20,30},{100,200,300},{1000,2000,3000}))
ok(sum[1]==1111 and sum[2]==2222 and sum[3]==3333,"four-vector placement sum")

local zero=assert(Attachment.resolve({flags=0x180,flags2=0x20},{commonOffset={1,2,3},transform={4,5,6},motion={7,8,9},scale=99}))
ok(zero.resolved and zero.anchor[2]==0 and zero.scale==1,"zero anchor and fixed scale")
ok(zero.position[1]==12 and zero.position[2]==15 and zero.position[3]==18,"zero anchor placement")
ok(zero.raw.contract.flags2==0x20,"flags2 preserved without inferred behavior")

local laneCalls=0
local lane=assert(Attachment.resolve({flags=0x480},{commonOffset={0,0,0},transform={0,0,0},motion={0,0,0},resolvers={laneScalar=function(ctx) laneCalls=laneCalls+1;return -2 end}}))
ok(laneCalls==1 and lane.anchor[1]==300 and lane.anchor[2]==0,"lane scalar times -150")

local yzero=assert(Attachment.resolve({flags=0x94},{commonOffset={0,0,0},transform={0,0,0},motion={0,0,0},resolvers={anchor=function()return{1,2,3}end}}))
ok(yzero.anchor[2]==0,"bit 4 forces anchor Y zero")
local ycall=assert(Attachment.resolve({flags=0x98},{commonOffset={0,0,0},transform={0,0,0},motion={0,0,0},resolvers={anchor=function()return{1,2,3}end,anchorY=function()return 44 end}}))
ok(ycall.anchor[2]==44,"bit 8 uses explicit Y callback")

local fallbackCalls=0
local model=assert(Attachment.resolve({flags=0xA0},{commonOffset={1,1,1},transform={0,0,0},motion={0,0,0},resolvers={modelAnchor=function()return nil end,anchor=function()fallbackCalls=fallbackCalls+1;return{2,3,4}end}}))
ok(model.resolved and fallbackCalls==1 and model.anchor[1]==2,"model callback falls back exactly")
local saved=assert(Attachment.resolve({flags=0xA0},{commonOffset={9,9,9},transform={1,1,1},motion={2,2,2},useSavedOrigin=true,savedOrigin={4,5,6},resolvers={modelAnchor=function()return{7,8,9}end}}))
ok(saved.commonOffset[1]==0 and saved.anchor[1]==4 and saved.position[1]==7,"saved origin clears common offset")

local shared=assert(Attachment.resolve({flags=0},{anchor={1,2,3},sharedOrigin={4,5,6},commonOffset={7,8,9},transform={0,0,0},motion={0,0,0}}))
ok(shared.position[1]==12 and shared.position[2]==15 and shared.position[3]==18,"shared origin adds to common offset")

local actor=assert(Attachment.resolve({flags=0x180},{commonOffset={0,0,0},transform={0,0,0},motion={0,0,0},actorTableRequired=true,resolvers={actorTable=function(anchor,ctx)return{anchor[1]+1,2,3}end}}))
ok(actor.anchor[1]==1,"actor-table resolver is explicit")

local context={effectId=3,programId=9,address=0x8417B624,commonOffset={0,0,0},transform={0,0,0},motion={0,0,0}}
local unresolved=assert(Attachment.resolve({flags=0x480},context))
local d=unresolved.diagnostic
ok(not unresolved.resolved and d.code=="unsupported-attachment-external","missing external is unresolved")
ok(d.effectId==3 and d.programId==9 and d.address==0x8417B624 and d.severity=="warning" and d.kind=="attachment","frozen diagnostic schema")
ok(select(1,Attachment.resolve({mode="world-origin"},{}))==nil,"contradicted old semantic contract rejected")

local mutable={flags=0x180};local detached=assert(Attachment.resolve(mutable,{commonOffset={0,0,0},transform={0,0,0},motion={0,0,0}}));detached.raw.contract.flags=0
ok(mutable.flags==0x180,"attachment result is detached")
print(("%d checks passed (Stadium 2 battle-FX routing/attachment)"):format(n))
