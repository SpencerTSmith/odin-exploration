#version 450 core

// So don't have to deal with geometry shader nonsense
#extension ARB_shader_viewport_layer_array : enable

layout (location = 0) in vec3 vert_position;

out VS_OUT {
  vec4 world_position;
} vs_out;

// We use the light geometry shader
uniform mat4 light_proj_view[6];
uniform mat4 model;

void main() {
  vec4 world_pos = model * vec4(vert_position, 1.0);

  gl_Position = light_proj_view[gl_InstanceID] * world_pos;
  gl_Layer = gl_InstanceID;

  vs_out.world_position = world_pos;
}
