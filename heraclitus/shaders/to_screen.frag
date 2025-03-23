#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

uniform sampler2D screen_texture;

out vec4 frag_color;

void main() {
  frag_color = texture(screen_texture, fs_in.uv);
}
