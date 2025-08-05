#version 450 core

// So don't have to deal with geometry shader nonsense
#extension GL_ARB_shader_viewport_layer_array : enable

layout (location = 0) in vec3 vert_position;

out VS_OUT {
  vec4 world_position;
  flat int  light_index;
} vs_out;

uniform mat4 model;

#include "include.glsl"

uniform mat4 test[6 * 16];

void main() {
  int light_index = gl_InstanceID / 6;
  int face_index  = gl_InstanceID % 6;

  Point_Light light = frame.lights.points[light_index];

  mat4 proj_view = light.proj_views[face_index];

  vec4 world_pos = model * vec4(vert_position, 1.0);

  gl_Position = proj_view * world_pos;
  gl_Layer    = gl_InstanceID;

  vs_out.world_position = world_pos;
  vs_out.light_index    = light_index;
}
