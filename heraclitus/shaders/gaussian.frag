#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

layout(binding = 0) uniform sampler2D image;

out vec4 frag_color;

// Averages the color of the samples
// vec4 sample_ms_texture(sampler2DMS texture, vec2 uv) {
//   ivec2 texture_coords = ivec2(uv * textureSize(texture));
//
//   vec4 color  = vec4(0.0);
//   int samples = textureSamples(texture);
//
//   for (int i = 0; i < samples; i++) {
//     color += texelFetch(texture, texture_coords, i);
//   }
//
//   return color / float(samples);
// }

uniform bool horizontal;
uniform float weight[5] = float[] (0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
  vec2 tex_size = 1.0 / textureSize(image, 0);
  vec3 result = texture(image, fs_in.uv).rgb * weight[0]; // current fragment's contribution
  if (horizontal)
  {
    // Sample the 5 texels to the right and left
    for (int i = 1; i < 5; ++i)
    {
      result += texture(image, fs_in.uv + vec2(tex_size.x * i, 0.0)).rgb * weight[i];
      result += texture(image, fs_in.uv - vec2(tex_size.x * i, 0.0)).rgb * weight[i];
    }
  }
  else
  {
    // Sample the 5 texels to the top and bottom
    for (int i = 1; i < 5; ++i)
    {
      result += texture(image, fs_in.uv + vec2(0.0, tex_size.y * i)).rgb * weight[i];
      result += texture(image, fs_in.uv - vec2(0.0, tex_size.y * i)).rgb * weight[i];
    }
  }

  frag_color = vec4(result, 1.0);
}
