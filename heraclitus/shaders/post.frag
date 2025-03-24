#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

uniform sampler2D screen_texture;

out vec4 frag_color;

const float offset = 1.0 / 300.0;

void main() {
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

  vec4 texture_color = texture(screen_texture, fs_in.uv);
  // float average = (texture_color.r + texture_color.g + texture_color.b) / 3.0;
  // float average = 0.2126 * texture_color.r + 0.7152 * texture_color.g + 0.0722 * texture_color.b;
  // frag_color = vec4(average, average, average, 1.0);
  frag_color = texture_color;
}
