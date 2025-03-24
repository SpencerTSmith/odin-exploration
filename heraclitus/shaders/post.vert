#version 450 core
layout(location = 0) in vec2 vert_position;
layout(location = 1) in vec2 vert_uv;

out VS_OUT {
  vec2 uv;
} vs_out;

void main() {
  vs_out.uv   = vert_uv;
  gl_Position = vec4(vert_position, 0.0, 1.0);
}
