#include <GLAD/glad.h>
#include <GLFW/glfw3.h>
#include <cglm/cglm.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

#define camera_rad_pp_x glm_rad(0.5)
#define camera_rad_pp_y glm_rad(0.5)
#define camera_max_pitch glm_rad(89.0)
#define camera_fwd_speed (float)400;

int res_w=1024;
int res_h=768;

typedef struct{
	vec3 fwd,up,rht,pos,ang;
	vec3 d_ang;
	int moved;
	float speed;
}Camera;

Camera cam={0,.pos={278,278,-800}};
vec3 x_axis={1.0,0.0,0.0};
vec3 y_axis={0.0,1.0,0.0};
GLFWwindow *main_window;

void MouseMove(GLFWwindow *wnd,double x,double y)
{
	double cx=(double)res_w*0.5;
	double cy=(double)res_h*0.5;
	double dx=cx-x;
	double dy=cy-y;
	cam.d_ang[0]+=(float)camera_rad_pp_x*(float)dy;
	cam.d_ang[1]+=(float)camera_rad_pp_y*(float)dx;
	cam.moved=1;
	//printf("%f,%f,%f\n",cam.d_ang[0],cam.d_ang[1],cam.d_ang[2]);
	glfwSetCursorPos(wnd,cx,cy);
}

void UpdateCameraAngleDeltas()
{
	cam.ang[0]+=cam.d_ang[0];
	cam.ang[1]+=cam.d_ang[1];
	if (cam.ang[0]>camera_max_pitch){
		cam.ang[0]=camera_max_pitch;
	}else if(cam.ang[0]<-camera_max_pitch){
		cam.ang[0]=-camera_max_pitch;
	}
	cam.d_ang[0]=0;
	cam.d_ang[1]=0;
}

void UpdateCamera(float dt)
{
	UpdateCameraAngleDeltas();
	cam.fwd[0]=0;
	cam.fwd[1]=0;
	cam.fwd[2]=-1;
	//camera angles
	glm_vec3_rotate(cam.fwd,cam.ang[0],x_axis);
	glm_vec3_rotate(cam.fwd,cam.ang[1],y_axis);
	//camera frame
	glm_vec3_cross(cam.fwd,y_axis,cam.rht);
	glm_vec3_normalize(cam.rht);
	glm_vec3_cross(cam.rht,cam.fwd,cam.up);
	glm_vec3_normalize(cam.up);
	vec3 speed;
	cam.speed=0;
	//controls
	if (glfwGetKey(main_window,GLFW_KEY_W)==GLFW_PRESS){
		cam.speed=camera_fwd_speed;
		cam.moved=1;
	}else if(glfwGetKey(main_window,GLFW_KEY_S)==GLFW_PRESS){
		cam.speed=-camera_fwd_speed;
		cam.moved=1;
	}
	//camera position
	glm_vec3_scale(cam.fwd,cam.speed*dt,speed);
	glm_vec3_add(cam.pos,speed,cam.pos);		
}

char *FileDump(char *file_name)
{
	int ln=strlen(file_name)+1;
	int pl=GetCurrentDirectory(0,NULL);
	char *pt=malloc(pl+ln);
	GetCurrentDirectory(pl,pt);
	memcpy(pt+pl,file_name,ln);
	pt[pl-1]='\\';
	FILE *fp=fopen(pt,"rb");
	if (fp==NULL){free(pt);return NULL;}
	free(pt);
	fseek(fp,0,SEEK_END);
	long sz=ftell(fp);
	printf("%d\n",sz);
	char *buf=malloc(sz+1);
	fseek(fp,0,SEEK_SET);
	fread(buf,1,sz,fp);
	buf[sz]='\0';
	fclose(fp);
	return buf;
}

int main()
{
	glfwInit();
	main_window=glfwCreateWindow(res_w,res_h,"GL",NULL,NULL);
	glfwMakeContextCurrent(main_window);
	gladLoadGLLoader((GLADloadproc)glfwGetProcAddress);
	glfwSetInputMode(main_window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
	glfwSetCursorPosCallback(main_window,MouseMove);
	glfwSetCursorPos(main_window,res_w*0.5,res_h*0.5);

	glViewport(0,0,res_w,res_h);

	int flag;

	const char *vertex_src=FileDump("shaders/vertex.glsl");
	if (vertex_src==NULL){printf("VertexShaderLoadError");goto quit;}
	int vs=glCreateShader(GL_VERTEX_SHADER);
	glShaderSource(vs,1,&vertex_src,NULL);
	glCompileShader(vs);
	glGetShaderiv(vs,GL_COMPILE_STATUS,&flag);
	if (flag!=GL_TRUE){
		char info[512]={'\0'};
		glGetShaderInfoLog(vs,512,NULL,info);
		printf("%s",info);
		goto quit;
	}
	const char *frag_src=FileDump("shaders/frag.glsl");
	if (frag_src==NULL){printf("FragShaderLoadError");goto quit;}			
	int fs=glCreateShader(GL_FRAGMENT_SHADER);
	glShaderSource(fs,1,&frag_src,NULL);
	glCompileShader(fs);	
	glGetShaderiv(fs,GL_COMPILE_STATUS,&flag);
	if (flag!=GL_TRUE){
		char info[512]={'\0'};
		glGetShaderInfoLog(fs,512,NULL,info);
		printf("%s",info);
		goto quit;
	}
	const char *comp_src=FileDump("shaders/compute.glsl");
	if (comp_src==NULL){printf("ComputeShaderLoadError");goto quit;}
	int cs=glCreateShader(GL_COMPUTE_SHADER);
	glShaderSource(cs,1,&comp_src,NULL);
	glCompileShader(cs);	
	glGetShaderiv(cs,GL_COMPILE_STATUS,&flag);
	if (flag!=GL_TRUE){
		char info[512]={'\0'};
		glGetShaderInfoLog(cs,512,NULL,info);
		printf("%s",info);
		goto quit;
	}	

	int compute_shader=glCreateProgram();
	glAttachShader(compute_shader,cs);
	glLinkProgram(compute_shader);
	glGetProgramiv(compute_shader,GL_LINK_STATUS,&flag);
	if (flag!=GL_TRUE){
		char info[512]={'\0'};
		glGetProgramInfoLog(compute_shader,512,NULL,info);
		printf("%s",info);
		goto quit;		
	}
	int vert_frag_shader=glCreateProgram();
	glAttachShader(vert_frag_shader,vs);
	glAttachShader(vert_frag_shader,fs);
	glLinkProgram(vert_frag_shader);	
	glGetProgramiv(vert_frag_shader,GL_LINK_STATUS,&flag);
	if (flag!=GL_TRUE){
		char info[512]={'\0'};
		glGetProgramInfoLog(vert_frag_shader,512,NULL,info);
		printf("%s",info);
		goto quit;		
	}

	glDeleteShader(vs);
	glDeleteShader(fs);
	glDeleteShader(cs);

	float qverts[]={
		-1,1,0,0,1,
		1,-1,0,1,0,
		-1,-1,0,0,0,
		-1,1,0,0,1,
		1,1,0,1,1,
		1,-1,0,1,0,
	};

	unsigned int quad,quad_vbuf;

	glGenBuffers(1,&quad_vbuf);
	glBindBuffer(GL_ARRAY_BUFFER,quad_vbuf);
	glBufferData(GL_ARRAY_BUFFER,sizeof(qverts),qverts,GL_STATIC_DRAW);

	glEnableVertexAttribArray(0);
	glEnableVertexAttribArray(1);
	glVertexAttribPointer(0,3,GL_FLOAT,GL_TRUE,5*sizeof(float),(void*)0);
	glVertexAttribPointer(1,2,GL_FLOAT,GL_TRUE,5*sizeof(float),(void*)(3*sizeof(float)));

	unsigned int img;

	glGenTextures(1,&img);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D,img);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
	glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,res_w,res_h,0,GL_RGBA,GL_FLOAT,NULL);
	glBindImageTexture(0,img,0,GL_FALSE,0,GL_READ_WRITE,GL_RGBA32F);

	unsigned int fbo;

	glGenFramebuffers(1,&fbo);
	glBindFramebuffer(GL_FRAMEBUFFER,fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,img,0);  
	glBindFramebuffer(GL_FRAMEBUFFER,0);

	float last_time=0;
	unsigned int frame=1;

	cam.moved=0;

	while (!glfwWindowShouldClose(main_window)){
		UpdateCamera((float)glfwGetTime()-last_time);
		last_time=glfwGetTime();

		if (cam.moved){
			glBindFramebuffer(GL_FRAMEBUFFER,fbo);
			glClearColor(0,0,0,1);
			glClear(GL_COLOR_BUFFER_BIT);
			glBindFramebuffer(GL_FRAMEBUFFER,0);
			cam.moved=0;
			frame=1;
		}

		glUseProgram(compute_shader);

		glUniform1ui(glGetUniformLocation(compute_shader,"frame"),frame);
		glUniform2f(glGetUniformLocation(compute_shader,"i_res"),res_w,res_h);
		glUniform1f(glGetUniformLocation(compute_shader,"aspect"),(float)res_w/(float)res_h);
		glUniform3f(glGetUniformLocation(compute_shader,"cam_up"),cam.up[0],cam.up[1],cam.up[2]);
		glUniform3f(glGetUniformLocation(compute_shader,"cam_rht"),cam.rht[0],cam.rht[1],cam.rht[2]);
		glUniform3f(glGetUniformLocation(compute_shader,"cam_fwd"),cam.fwd[0],cam.fwd[1],cam.fwd[2]);
		glUniform3f(glGetUniformLocation(compute_shader,"cam_pos"),cam.pos[0],cam.pos[1],cam.pos[2]);

		glDispatchCompute(res_w,res_h,1);
		
		glUseProgram(vert_frag_shader);
		glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
		glDrawArrays(GL_TRIANGLES,0,6);

		glfwSwapBuffers(main_window);

		glfwPollEvents();

		frame++;
	}

	quit:
	glfwTerminate();
	return 0;
}