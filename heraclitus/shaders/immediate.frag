#version 450

in VS_OUT {
  vec2 uv;
  vec4 color;
} fs_in;

out vec4 frag_color;

uniform sampler2D tex;

void main() {
  frag_color = texture(tex, fs_in.uv) * fs_in.color;
}
