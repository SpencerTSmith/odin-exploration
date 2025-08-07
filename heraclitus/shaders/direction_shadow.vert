#version 450 core

layout (location = 0) in vec3 vert_position;

uniform mat4 model;

#include "include.glsl"

void main() {
  mat4 proj_view = frame.lights.direction.proj_view;

  gl_Position = proj_view * model * vec4(vert_position, 1.0);
}
