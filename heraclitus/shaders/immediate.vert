#version 450 core

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec4 vert_color;

out VS_OUT {
  vec2 uv;
  vec4 color;
} vs_out;

#include "include.glsl"

uniform mat4 transform;

void main() {
  vs_out.uv    = vert_uv;
  vs_out.color = vert_color;

  gl_Position = transform * vec4(vert_position, 1.0);
}
