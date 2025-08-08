#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

layout(binding = 0) uniform sampler2DMS screen_texture;

uniform float exposure = 1.0;

out vec4 frag_color;

// Averages the color of the samples
vec4 sample_ms_texture(sampler2DMS texture, vec2 uv) {
  ivec2 texture_coords = ivec2(uv * textureSize(texture));

  vec4 color  = vec4(0.0);
  int samples = textureSamples(texture);

  for (int i = 0; i < samples; i++) {
    color += texelFetch(texture, texture_coords, i);
  }

  return color / float(samples);
}

void main() {
  vec3 hdr_color = sample_ms_texture(screen_texture, fs_in.uv).rgb;

  // Reinhard
  vec3 mapped = hdr_color / (hdr_color + vec3(1.0));

  // Exposure
  // vec3 mapped = vec3(1.0) - exp(-hdr_color * exposure);

  // gamma correct
  const float gamma = 2.2;
  mapped = pow(mapped, vec3(1.0 / gamma));

  frag_color = vec4(mapped, 1.0);
}
