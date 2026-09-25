-- Four tiny local sources, no shadow maps or additional render passes.
local L={}
L.pixel=[[
uniform float fireflyEnabled;
uniform vec4 firefly1;uniform vec4 firefly2;uniform vec4 firefly3;uniform vec4 firefly4;
float fireflyPoint(vec4 light,vec3 p,vec3 n){
 vec3 delta=light.xyz-p;float distanceSquared=dot(delta,delta);
 float falloff=max(0.,1.-distanceSquared/(26.*26.));
 float facing=.2+.8*max(0.,dot(n,delta*inversesqrt(max(.001,distanceSquared))));
 return light.w*falloff*falloff*facing;
}
vec3 fireflyLight(vec3 p,vec3 n){
 if(fireflyEnabled<.5)return vec3(0.);
 float amount=fireflyPoint(firefly1,p,n)+fireflyPoint(firefly2,p,n)
  +fireflyPoint(firefly3,p,n)+fireflyPoint(firefly4,p,n);
 return vec3(.80,1.,.34)*amount;
}
]]
return L
