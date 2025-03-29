#version 450 core

layout (location = 0) in vec3 vert_position;

// The light's projection and view matrix
uniform mat4 light_proj_view;
uniform mat4 model;

void main() {
  gl_Position = light_proj_view * model * vec4(vert_position, 1.0);
}
