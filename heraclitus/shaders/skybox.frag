#version 450 core

in VS_OUT {
  vec3 uvw;
} fs_in;

#include "include.glsl"

layout(binding = 0) uniform samplerCube skybox;

out vec4 frag_color;

float linearize_depth(float depth, float near, float far) {
  float ndc = (depth * 2.0) - 1.0;
  // Unproject basically
  float linear_depth = (2.0 * near * far) / (far + near - ndc * (far - near));

  return linear_depth;
}

vec3 depth_to_color(float linear_depth, float far) {
  float normalized_depth = clamp((linear_depth / far), 0.0, 1.0);

  float brightness = normalized_depth;

  return brightness * vec3(1.0, 0.0, 0.0);
}

void main() {
  vec4 result = vec4(0.0);
  switch (frame.debug_mode) {
  case DEBUG_MODE_NONE:
    result = texture(skybox, fs_in.uvw);
    break;

  case DEBUG_MODE_DEPTH:
    float depth = gl_FragCoord.z;
    float linear_depth = linearize_depth(depth, frame.z_near, frame.z_far);
    result = vec4(depth_to_color(linear_depth, frame.z_far), 1.0);
    break;
  }

  frag_color = result;
}
