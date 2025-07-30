#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

out vec4 frag_color;

#include "include.glsl"

uniform vec4     mul_color;
uniform Material material;

void main() {
  frag_color = texture(material.diffuse, fs_in.uv) * mul_color;
}
