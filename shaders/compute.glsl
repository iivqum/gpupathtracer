#version 430
layout(local_size_x=1,local_size_y=1) in;
layout(binding=0,rgba32f) uniform image2D framebuffer;

#define MATERIAL_DIFFUSE 0
#define MATERIAL_METALLIC 1
#define MATERIAL_DIELECTRIC 3

#define RECT_XY 0
#define RECT_XZ 1
#define RECT_YZ 3

#define num_spheres 3
#define num_rects 5

uniform uint frame;
uniform float aspect;
uniform vec2 i_res;
uniform vec3 cam_up;
uniform vec3 cam_pos;
uniform vec3 cam_rht;
uniform vec3 cam_fwd;

const float pi=3.14159;
const int samples_per_pixel=2;

//xorshift state
uint xs_state;

struct Material{
	int type;
	vec3 albedo,emissive;
	float roughness;
	float refract_idx;
};

struct Sphere{
	vec3 pos;
	float radius;
	Material material;
};

struct Rect{
	int type;
	float cord[5];
	//true positive normal false negative normal
	bool face;
	Material material;
};

struct Ray{
	vec3 pos,dir;
};

struct RayResult{
	Material material;
	vec3 pos,normal;
	Ray ray;
};

Sphere spheres[num_spheres];
Rect rects[num_rects];

//use this to seed xorshift
uint Wang(uint seed)
{
	seed^=61^(seed>>16);
	seed*=9;
	seed^=seed>>4;
	seed*=0x27d4eb2d;
	seed^=seed>>15;
	return seed;
}

uint XORShift()
{
	xs_state^=xs_state<<13;
	xs_state^=xs_state>>17;
	xs_state^=xs_state<<5;
	return xs_state;
}

float RNGFloat()
{
	return float(XORShift())/4294967296.0;
}

vec3 SampleSphere()
{
	float d=RNGFloat()*2.0-1.0;
	float a=RNGFloat()*2*pi;
	float r=sqrt(1-d*d);
	return vec3(r*cos(a),r*sin(a),d);
}

void ScatterDiffuse(out Ray ray,in RayResult res)
{
	ray.dir=normalize(res.normal+SampleSphere());
}

void ScatterMetal(inout Ray ray,in RayResult res)
{
	ray.dir=normalize(reflect(ray.dir,res.normal)+SampleSphere()*res.material.roughness);
}

float Schlick(float co,float idx)
{
	float r0=(1-idx)/(1+idx);
	r0*=r0;
	return r0+(1-r0)*pow(1-co,5);
}

bool Refract(in Ray ray,in vec3 normal,float ratio,out vec3 ref_ray)
{
	float co=dot(ray.dir,normal);
	float d=1-ratio*ratio*(1-co*co);
	if (d>0){
		ref_ray=normalize(ratio*(ray.dir-normal*co)-normal*sqrt(d));
		return true;
	}
	return false;
}

void ScatterDielectric(inout Ray ray,in RayResult res)
{
	vec3 normal;
	float n1_over_n2;
	float co;
	if (dot(ray.dir,res.normal)>0){
		n1_over_n2=res.material.refract_idx;
		normal=-res.normal;
		co=dot(ray.dir,res.normal);
	}else{
		n1_over_n2=1/res.material.refract_idx;
		normal=res.normal;
		co=-dot(ray.dir,res.normal);		
	}
	float reflect_prob;
	vec3 refract_ray;
	if (Refract(ray,normal,n1_over_n2,refract_ray)){
		reflect_prob=Schlick(co,res.material.refract_idx);
	}else{
		reflect_prob=1.0;
	}
	if (RNGFloat()<reflect_prob){
		ray.dir=reflect(ray.dir,res.normal);
	}else{
		ray.dir=refract_ray;
	}
}

bool TestRaySphere(inout float tmax,in Ray ray,in Sphere sphere,inout RayResult res)
{
	vec3 oc=ray.pos-sphere.pos;
	float a=dot(ray.dir,ray.dir);
	float b=2*dot(oc,ray.dir);
	float c=dot(oc,oc)-sphere.radius*sphere.radius;
	float d=b*b-4*a*c;
	if (d<=0)
		return false;
	d=sqrt(d);
	a=1/(2*a);
	float r=(-b-d)*a;
	if (r>1e-3&&r<tmax){
		tmax=r;
		res.pos=ray.pos+ray.dir*r;
		res.normal=(res.pos-sphere.pos)/sphere.radius;
		return true;
	}
	r=(-b+d)*a;
	if (r>1e-3&&r<tmax){
		tmax=r;
		res.pos=ray.pos+ray.dir*r;
		res.normal=(res.pos-sphere.pos)/sphere.radius;
		return true;
	}
	return false;
}

bool TestRayRect(inout float tmax,in Ray ray,in Rect rect,inout RayResult res)
{
	float b0,b1,t;
	vec3 normal;
	if (rect.type==RECT_XY){
		normal=vec3(0,0,1);
		t=(rect.cord[4]-ray.pos.z)/ray.dir.z;
		b0=ray.pos.x+t*ray.dir.x;
		b1=ray.pos.y+t*ray.dir.y;
	}else if (rect.type==RECT_XZ){
		normal=vec3(0,1,0);
		t=(rect.cord[4]-ray.pos.y)/ray.dir.y;
		b0=ray.pos.x+t*ray.dir.x;
		b1=ray.pos.z+t*ray.dir.z;
	}else if (rect.type==RECT_YZ){
		normal=vec3(1,0,0);
		t=(rect.cord[4]-ray.pos.x)/ray.dir.x;
		b0=ray.pos.y+t*ray.dir.y;
		b1=ray.pos.z+t*ray.dir.z;
	}else{return false;}
	if (t<1e-3||t>tmax)
		return false;
	if (b0<rect.cord[0]||b0>rect.cord[1]||b1<rect.cord[2]||b1>rect.cord[3])
		return false;
	if (rect.face==false)
		normal*=-1;
	res.normal=normal;
	res.pos=ray.pos+ray.dir*t;
	tmax=t;
	return true;
}

bool TestRayScene(in Ray ray,inout RayResult res)
{
	float tmax=1e+38;
	bool hit=false;
	for (int i=0;i<num_spheres;i++){
		if (TestRaySphere(tmax,ray,spheres[i],res)){
			res.material=spheres[i].material;
			hit=true;
		}
	}
	for (int i=0;i<num_rects;i++){
		if (TestRayRect(tmax,ray,rects[i],res)){
			res.material=rects[i].material;
			hit=true;
		}
	}
	return hit;
}

vec3 Trace(in Ray ray)
{
	RayResult result;
	vec3 color=vec3(0,0,0);
	vec3 reflectance=vec3(1,1,1);
	for (int i=0;i<10;i++){
		if (TestRayScene(ray,result)==false){
			float t=(ray.dir.y+1)*0.5;
			color+=(1-t)*vec3(1)+t*vec3(0.5,0.7,1.0);
			break;
		}
		switch(result.material.type){
			case MATERIAL_DIFFUSE:
				ScatterDiffuse(ray,result);
				break;
			case MATERIAL_METALLIC:
				ScatterMetal(ray,result);
				break;
			case MATERIAL_DIELECTRIC:
				ScatterDielectric(ray,result);
				break;
		}
		ray.pos=result.pos;
		color+=result.material.emissive;
		reflectance*=result.material.albedo;
		//color*=dot(ray.dir,result.normal);
		//ray.pos+=result.normal*0.001;
	}
	color*=reflectance;
	return color;
}

Rect QuickRect(int type,float c0,float c1,float c2,float c3,float k,bool face)
{
	Rect rect;
	rect.cord[0]=c0;
	rect.cord[1]=c1;
	rect.cord[2]=c2;
	rect.cord[3]=c3;
	rect.cord[4]=k;
	rect.face=face;
	rect.type=type;
	return rect;
}

void main()
{
	//seed xorshift
	xs_state=Wang((uint(gl_GlobalInvocationID.x)*uint(1973) +uint(gl_GlobalInvocationID.y)*uint(9277)+frame*uint(26699))|1)|1;

	ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);

	rects[0]=QuickRect(RECT_YZ,0,555,0,555,555,false);
	rects[0].material.type=MATERIAL_DIFFUSE;
	rects[0].material.albedo=vec3(0.12,0.45,0.15);
	rects[0].material.emissive=vec3(0);
	rects[0].material.roughness=0.01;

	rects[1]=QuickRect(RECT_YZ,0,555,0,555,0,true);
	rects[1].material.type=MATERIAL_DIFFUSE;
	rects[1].material.albedo=vec3(0.65,0.05,0.05);
	rects[1].material.emissive=vec3(0);
	rects[1].material.roughness=0.01;

	rects[2]=QuickRect(RECT_XZ,0,555,0,555,0,true);
	rects[2].material.type=MATERIAL_DIFFUSE;
	rects[2].material.albedo=vec3(0.73,0.73,0.73);
	rects[2].material.emissive=vec3(0);

	rects[3]=QuickRect(RECT_XZ,0,555,0,555,555,false);
	rects[3].material.type=MATERIAL_DIFFUSE;
	rects[3].material.albedo=vec3(0.73,0.73,0.73);
	rects[3].material.emissive=vec3(0);

	rects[4]=QuickRect(RECT_XY,0,555,0,555,555,false);
	rects[4].material.type=MATERIAL_DIFFUSE;
	rects[4].material.albedo=vec3(0.73,0.73,0.73);
	rects[4].material.emissive=vec3(0);

	spheres[0].pos=vec3(256,50,256);
	spheres[0].radius=50;
	spheres[0].material.type=MATERIAL_DIFFUSE;
	spheres[0].material.albedo=vec3(0.8);
	spheres[0].material.emissive=vec3(0);
	spheres[0].material.refract_idx=2.05;

	spheres[1].pos=vec3(256+101,50,256);
	spheres[1].radius=50;
	spheres[1].material.type=MATERIAL_DIELECTRIC;
	spheres[1].material.albedo=vec3(0.97);
	spheres[1].material.emissive=vec3(0);
	spheres[1].material.refract_idx=2.05;

	spheres[2].pos=vec3(256-101,50,256);
	spheres[2].radius=50;
	spheres[2].material.type=MATERIAL_DIELECTRIC;
	spheres[2].material.albedo=vec3(0.97);
	spheres[2].material.emissive=vec3(0);
	spheres[2].material.refract_idx=2.05;

	Ray ray;
	
	vec3 color=vec3(0);
	for (int i=0;i<samples_per_pixel;i++){
		//texture space, bottom left is 0,0
		vec2 ndc=vec2(2,2)*((pixel+vec2(RNGFloat(),RNGFloat()))/i_res)+vec2(-1,-1);
		ray.dir=normalize(ndc.x*cam_rht*aspect+ndc.y*cam_up+cam_fwd);
		ray.pos=cam_pos;
		color+=Trace(ray);
	}
	color/=samples_per_pixel;

	vec4 prev=imageLoad(framebuffer,pixel);
	vec4 new=prev+(vec4(color,1)-prev)/frame;

	imageStore(framebuffer,pixel,new);
}