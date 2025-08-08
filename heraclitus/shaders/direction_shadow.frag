#version 450 core

#include "include.glsl"

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;

out VS_OUT {
  vec2 uv;
} vs_out;

uniform mat4 model;

layout(binding = 0) uniform sampler2D mat_diffuse;

void main() {
  float alpha = texture(mat_diffuse, fs_in.uv).a;

  if (alpha < 0.5) {
    discard;
  }
}
