-- Matching cube-face bases for CPU shadow cameras and GLES2 atlas sampling.
local P={size=256,range=100}
P.faces={
 {f={1,0,0},r={0,0,-1},u={0,1,0}},
 {f={-1,0,0},r={0,0,1},u={0,1,0}},
 {f={0,1,0},r={1,0,0},u={0,0,-1}},
 {f={0,-1,0},r={1,0,0},u={0,0,1}},
 {f={0,0,1},r={1,0,0},u={0,1,0}},
 {f={0,0,-1},r={-1,0,0},u={0,1,0}},
}
function P.view(p,i)
 local b=P.faces[i];local f,r,u=b.f,b.r,b.u
 local x,y,z=p[1],p[2]+1,p[3]
 return {r[1],r[2],r[3],-r[1]*x-r[2]*y-r[3]*z,
 u[1],u[2],u[3],-u[1]*x-u[2]*y-u[3]*z,
 -f[1],-f[2],-f[3],f[1]*x+f[2]*y+f[3]*z,0,0,0,1}
end
P.source=[[
vec2 torchAtlasUV(vec3 v){
 vec3 a=abs(v);vec2 q;float face;float major;
 if(a.x>=a.y && a.x>=a.z){major=a.x;if(v.x>=0.){q=vec2(-v.z,v.y);face=0.;}else{q=vec2(v.z,v.y);face=1.;}}
 else if(a.y>=a.z){major=a.y;if(v.y>=0.){q=vec2(v.x,-v.z);face=2.;}else{q=vec2(v.x,v.z);face=3.;}}
 else{major=a.z;if(v.z>=0.){q=vec2(v.x,v.y);face=4.;}else{q=vec2(-v.x,v.y);face=5.;}}
 q=clamp(q/max(major,.0001)*.5+.5,vec2(.5/256.),vec2(255.5/256.));
 return (q+vec2(mod(face,3.),floor(face/3.)))/vec2(3.,2.);
}
float torchCompare(Image map,vec3 ray,float receiver){
 vec4 d=Texel(map,torchAtlasUV(ray));
 return smoothstep(receiver-.001,receiver+.001,d.r+d.g/255.);
}
float torchVisibility(Image map,vec3 light,vec3 p,vec3 n){
 // Most forest pixels lie outside either torch. Skip all four atlas taps
 // before computing the filter basis; the lighting falloff is already zero.
 vec3 delta=p-light;
 if(dot(delta,delta)>=10000.)return 1.;
 vec3 ray=delta+n*.18;
 float distance=length(ray);
 vec3 dir=ray/max(distance,.0001);
 // World-space bias is independent of face orientation and perspective depth.
 float bias=mix(.10,.32,1.-max(0.,dot(n,-dir)));
 float receiver=(distance-bias)/100.;
 vec3 tangent=normalize(cross(dir,abs(dir.y)<.9?vec3(0.,1.,0.):vec3(1.,0.,0.)));
 vec3 bitangent=cross(dir,tangent);
 // Perturb directions before face selection: filter taps cross cube seams safely.
 float radius=max(.08,distance/256.);
 return .25*(torchCompare(map,ray+radius*(tangent+bitangent),receiver)
 +torchCompare(map,ray+radius*(tangent-bitangent),receiver)
 +torchCompare(map,ray+radius*(-tangent+bitangent),receiver)
 +torchCompare(map,ray-radius*(tangent+bitangent),receiver));
}
]]
return P
