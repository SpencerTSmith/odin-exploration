#version 450 core

layout(location = 0) in vec2 vert_position;
layout(location = 1) in vec4 vert_color;

out VS_OUT {
  vec4 color;
} vs_out;

void main() {
  vs_out.color = vert_color;
  gl_Position = vec4(vert_position, 0.0, 1.0);
}
