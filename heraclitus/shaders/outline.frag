#version 450 core

in VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
} fs_in;

out vec4 out_color;

uniform vec3 outline_color;

void main() {
  out_color = vec4(outline_color, 1.0);
}
