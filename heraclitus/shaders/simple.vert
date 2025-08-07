#version 450 core

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec3 vert_normal;

out VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
  vec4 sun_space_position;
} vs_out;

#include "include.glsl"

uniform mat4 model;

void main() {
  vs_out.uv = vert_uv;

	vs_out.world_position     = vec3(model * vec4(vert_position, 1.0));

  mat4 sun_proj_view = frame.lights.direction.proj_view;
  vs_out.sun_space_position = sun_proj_view * vec4(vs_out.world_position, 1.0);

	// FIXME: slow, probably
	vs_out.normal = transpose(inverse(mat3(model))) * vert_normal;

  // gl_Position = frame.projection * frame.view * vec4(vs_out.world_position, 1.0);
  gl_Position = frame.proj_view * vec4(vs_out.world_position, 1.0);
}
