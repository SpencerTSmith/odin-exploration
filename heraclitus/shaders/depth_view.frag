#version 450 core

in vec2 frag_uv;
in vec3 frag_normal;
in vec3 frag_world_position;

out vec4 frag_color;

#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
	mat4 projection;
	mat4 view;
	vec4 camera_position;
  float z_near;
  float z_far;
} frame;

float linearize_depth(float depth, float near, float far) {
  float ndc = (depth * 2.0) - 1.0;
  // Unproject basically
  float linear_depth = (2.0 * near * far) / (far + near - ndc * (far - near));
  return linear_depth;
}

vec3 depth_to_color(float linear_depth, float far) {
  float normalized_depth = clamp((linear_depth / far), 0.0, 1.0);

  float brightness = 1.0 - normalized_depth;

  return brightness * vec3(1.0, 0.8, 0.3);
}

void main() {
  float depth = gl_FragCoord.z;
  float linear_depth = linearize_depth(depth, frame.z_near, frame.z_far);
  vec3 colorized = depth_to_color(linear_depth, frame.z_far);

  frag_color = vec4(vec3(colorized), 1.0);
}
