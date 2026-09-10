-- Optional torch lighting for either model shader tier. Defaults disabled.
local M={}
M.pixel=[[
uniform float localTorchEnabled;uniform float localTorchShadows;
uniform vec3 localTorch1;uniform vec3 localTorch2;

uniform Image localTorchMap1;uniform Image localTorchMap2;
uniform float localTorchPower;
]]..require("mods.STADIUM2_IMPORTER.lib.torch_projection").source..[[
float modelTorchVisibility(Image map,vec3 light,vec3 p,vec3 n){
 if(localTorchShadows<.5)return 1.;
 return torchVisibility(map,light,p,n);
}
vec3 localTorchLight(vec3 p,vec3 n){
 if(localTorchEnabled<.5)return vec3(0.);
 vec3 a=localTorch1-p,b=localTorch2-p;
 float fa=max(0.,1.-length(a)/100.);float fb=max(0.,1.-length(b)/100.);
 float la=fa*fa*(.30+.70*max(0.,dot(n,normalize(a))))*modelTorchVisibility(localTorchMap1,localTorch1,p,n);
 float lb=fb*fb*(.30+.70*max(0.,dot(n,normalize(b))))*modelTorchVisibility(localTorchMap2,localTorch2,p,n);
 return vec3(1.65,.75,.22)*(la+lb)*localTorchPower;
}
]]
function M.apply(source)
 source=source:gsub('varying STADIUM_FLOAT vec3 vNormal;',
  'varying STADIUM_FLOAT vec3 vNormal;\nvarying STADIUM_FLOAT vec3 vTorchWorld;',1)
 if not source:find('uniform mat4 modelMatrix;',1,true) then
  source=source:gsub('uniform mat4 mvp;', 'uniform mat4 mvp;\nuniform mat4 modelMatrix;',1)
 end
 source=source:gsub('vec4 clip=mvp%*vertex_position;',
  'vTorchWorld=(modelMatrix*vertex_position).xyz;\n  vec4 clip=mvp*vertex_position;',1)
 source=source:gsub('#ifdef PIXEL',function() return '#ifdef PIXEL\n'..M.pixel end,1)
 source=source:gsub('(vec3 shaded%s*=%s*combined%s*%*%s*lighting%s*%*%s*sceneTint%.rgb;)',
  '%1\n  shaded+=combined*localTorchLight(vTorchWorld,n);',1)
 return source
end
return M
