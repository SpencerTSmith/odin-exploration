#version 450 core

layout (location = 0) in vec3 vert_position;

out VS_OUT {
  vec3 uvw;
} vs_out;

#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
	mat4  projection;
	mat4  view;
	vec4  camera_position;
  float z_near;
  float z_far;
  int   debug_mode;
  vec4  scene_extents;
} frame;
#define DEBUG_MODE_NONE  0
#define DEBUG_MODE_DEPTH 1

void main() {
  vs_out.uvw = vert_position;

  // View without translation transformations, gives the effect of a HUGE cube
  mat4 view_mod = mat4(mat3(frame.view));
  vec4 position = frame.projection * view_mod * vec4(vert_position, 1.0);
  // And save w in z as well so that after perspective divice, the position will have the max depth
  // and thus fail all depth tests, meaning it get overwritten
  gl_Position   = position.xyww;
}
