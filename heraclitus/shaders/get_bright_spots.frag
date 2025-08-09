#version 450 core

in VS_OUT {
  vec2 uv;
} fs_in;

layout(binding = 0) uniform sampler2D image;

layout(location = 0) out vec4 frag_color;
layout(location = 1) out vec4 bright_color;

void main() {
  frag_color = texture(image, fs_in.uv);

  float brightness = dot(frag_color.rgb, vec3(0.2126, 0.7152, 0.0722));

  if (brightness > 1.985) {
    bright_color = vec4(frag_color.rgb, 1.0);
  } else {
    bright_color = vec4(0.0, 0.0, 0.0, 1.0);
  }
}
