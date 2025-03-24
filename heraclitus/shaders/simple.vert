#version 450 core

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec3 vert_normal;

out VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
} vs_out;

#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
	mat4  projection;
	mat4  view;
	vec4  camera_position;
  float z_near;
  float z_far;
  int   debug_mode;
} frame;
#define DEBUG_MODE_NONE  0
#define DEBUG_MODE_DEPTH 1

uniform mat4 model;

void main() {
    gl_Position = frame.projection * frame.view * model * vec4(vert_position, 1.0);

    vs_out.uv             = vec2(vert_uv.x, vert_uv.y);
		vs_out.world_position = vec3(model * vec4(vert_position, 1.0));

		// FIXME: slow, probably
		vs_out.normal = mat3(transpose(inverse(model))) * vert_normal;
}
