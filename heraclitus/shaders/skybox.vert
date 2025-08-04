#version 450 core

layout(location = 0) in vec3 vert_position;

out VS_OUT {
  vec3 uvw;
} vs_out;

#include "include.glsl"

void main() {
  vs_out.uvw = vert_position;

  // View without translation transformations, gives the effect of a HUGE cube
  mat4 view_mod = mat4(mat3(frame.view));
  vec4 position = frame.projection * view_mod * vec4(vert_position, 1.0);

  // And save w in z as well so that after perspective divice, the position will have the max depth
  // and thus fail all depth tests, meaning it get overwritten
  gl_Position   = position.xyww;
}
