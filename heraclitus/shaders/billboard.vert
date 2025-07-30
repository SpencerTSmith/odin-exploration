#version 450 core

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec3 vert_normal;

out VS_OUT {
  vec2 uv;
} vs_out;

#include "include.glsl"

uniform mat4 light_proj_view;
uniform mat4 model;

void main() {
  vs_out.uv = vert_uv;

  // The center of this billboard
	vec3 center_position = vec3(model * vec4(0.0, 0.0, 0.0, 1.0));

  vec3 cam_to_pos = normalize(frame.camera_position.xyz - center_position);
  vec3 world_up = vec3(0, 1, 0);
  vec3 right = normalize(cross(world_up, cam_to_pos));
  vec3 up    = normalize(cross(cam_to_pos, right));

  // Now the using the right and up (from the billboard to cam) as our basis vectors
  // (basically, take the normal vertex x and say how far is it right in this new right direction, vice versa for y)
  // recalculate the new vertex position
  vec3 world_position = center_position + (vert_position.x * right) + (vert_position.y * up);

  gl_Position = frame.projection * frame.view * vec4(world_position, 1.0);
}
