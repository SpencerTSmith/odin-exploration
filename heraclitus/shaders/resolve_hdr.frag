#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

layout(binding = 0) uniform sampler2D screen_texture;
layout(binding = 1) uniform sampler2D bloom_blur;

uniform float exposure = 1.0;

out vec4 frag_color;

void main() {
  vec3 hdr_color   = texture(screen_texture, fs_in.uv).rgb;
  vec3 bloom_color = texture(bloom_blur, fs_in.uv).rgb;

  hdr_color += bloom_color;

  // Reinhard
  vec3 mapped = hdr_color / (hdr_color + vec3(1.0));

  // Exposure
  // vec3 mapped = vec3(1.0) - exp(-hdr_color * exposure);

  // gamma correct
  const float gamma = 2.2;
  mapped = pow(mapped, vec3(1.0 / gamma));

  frag_color = vec4(mapped, 1.0);
}
