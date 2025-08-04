#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

out vec4 frag_color;

#include "include.glsl"

layout(binding = 0) uniform sampler2D mat_diffuse;
// layout(binding = 1) uniform sampler2D mat_specular;
// layout(binding = 2) uniform sampler2D mat_emissive;
uniform float mat_shininess;

uniform vec4     mul_color;

void main() {
  frag_color = texture(mat_diffuse, fs_in.uv) * mul_color;
}
