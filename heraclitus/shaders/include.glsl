#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
  mat4  projection;
  mat4  orthographic;
  mat4  view;
  vec4  camera_position;
  float z_near;
  float z_far;
  int   debug_mode;
  vec4  scene_extents;
} frame;
#define DEBUG_MODE_NONE  0
#define DEBUG_MODE_DEPTH 1
