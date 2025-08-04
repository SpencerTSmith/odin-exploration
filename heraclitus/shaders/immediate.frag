#version 450

in VS_OUT {
  vec2 uv;
  vec4 color;
} fs_in;

out vec4 frag_color;

layout(binding = 0) uniform sampler2D tex;

void main() {
  // float alpha = texture(tex, fs_in.uv).r * fs_in.color.a;
  frag_color = texture(tex, fs_in.uv) * fs_in.color;
}
