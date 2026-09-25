local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local Material=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_material")
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local controller={period=2,mode=1,texturePointers={100,200},
  tileScroll={baseS=0,baseT=0,speedS=4,speedT=4,width=32,height=32}}
local prim={material={primitiveColor={1,1,1,1}},battleFxController={items={
  {textureUnit=0,texturePointer=100,textureWidth=32,textureHeight=32,controller=controller},
  {textureUnit=1,texturePointer=300}}}}
local renderer=setmetatable({model={textures={{sourcePointer=100},{sourcePointer=200},{sourcePointer=300}}},
  handlerRuntime={callbackFrame=0}},{__index=Renderer})
local a=renderer:battleFxMaterialState(prim)
check(renderer:currentTexture(prim)==1 and a.textures[2]==3,"both texture units resolve source pointers")
check(renderer:battleFxMaterialState(prim)==a,"repeated draws reuse the same tick evaluation")
renderer.handlerRuntime.callbackFrame=2
local b=renderer:battleFxMaterialState(prim)
check(renderer:currentTexture(prim)==2 and b~=a,"authored period advances texture")
check(b.textures.scroll[1][1]==1/32 and b.textures.scroll[1][2]==-1/32,"authored tile motion reaches renderer state")
renderer.handlerRuntime.callbackFrame=100
check(renderer:currentTexture(prim)==2,"one-shot texture animation clamps instead of looping")
local state=Material.init({nativeMaterialColors=true,nativePrimaryTrack={mode=1,period=3,
  colors={{age=0,rgba={0,100,200,255}},{age=2,rgba={100,0,0,55}}}},
  nativeSecondaryTrack={mode=0,period=2,colors={{1,2,3,4},{5,6,7,8}}}}, {})
state=Material.step(state,{age=1})
check(state.primaryColor[1]==50 and state.nativeAlpha==155,"primary RGB and alpha interpolate persistently")
check(state.secondaryColor[1]==5,"secondary track advances independently")
state=Material.step(state,{age=20})
check(state.primaryColor[1]==100 and state.nativeAlpha==55,"particle tracks hold their terminal sample")
check(state.secondaryColor[1]==5,"secondary track clamps at its own period")
print(checks.." checks passed (battle FX animated materials)")
