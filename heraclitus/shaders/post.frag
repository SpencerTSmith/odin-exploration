#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

layout(binding = 0) uniform sampler2DMS screen_texture;

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
  // const float offset = 1.0 / 300.0;
  // vec2 offsets[9] = vec2[](
  //   vec2(-offset,  offset), // top-left
  //   vec2( 0.0f,    offset), // top-center
  //   vec2( offset,  offset), // top-right
  //   vec2(-offset,  0.0f),   // center-left
  //   vec2( 0.0f,    0.0f),   // center-center
  //   vec2( offset,  0.0f),   // center-right
  //   vec2(-offset, -offset), // bottom-left
  //   vec2( 0.0f,   -offset), // bottom-center
  //   vec2( offset, -offset)  // bottom-right
  // );
  //
  // float kernel[9] = float[](
  //   1,  1,  1,
  //   1, -8,  1,
  //   1,  1,  1
  // );
  //
  // vec3 sampled_colors[9];
  // for (int i = 0; i < 9; i++) {
  //   sampled_colors[i] = vec3(texture(screen_texture, fs_in.uv + offsets[i]));
  // }
  //
  // vec3 kerneled_color = vec3(0.0);
  // for (int i = 0; i < 9; i++) {
  //   kerneled_color += sampled_colors[i] * kernel[i];
  // }
  //
  // frag_color = vec4(kerneled_color, 1.0);

  // float average = (texture_color.r + texture_color.g + texture_color.b) / 3.0;
  // float average = 0.2126 * texture_color.r + 0.7152 * texture_color.g + 0.0722 * texture_color.b;
  // frag_color = vec4(average, average, average, 1.0);

  vec4 texture_color = sample_ms_texture(screen_texture, fs_in.uv);
  const float gamma = 2.2;

  frag_color = vec4(pow(texture_color.rgb, vec3(1.0/gamma)), 1.0);
}
