#version 450 core

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec4 vert_color;

out VS_OUT {
  vec2 uv;
  vec4 color;
} vs_out;

#include "include.glsl"

void main() {
  vs_out.uv    = vert_uv;
  vs_out.color = vert_color;

  // Put it on the near plane
  gl_Position = frame.orthographic * vec4(vert_position, 1.0);
}
