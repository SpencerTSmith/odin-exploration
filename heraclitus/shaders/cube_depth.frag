#version 330 core

in VS_OUT {
  vec4 world_position;
} fs_in;

uniform vec3 light_pos;
uniform float far_plane;

void main() {
  // get distance between fragment and light source
  float light_dist = length(fs_in.world_position.xyz - light_pos);

  // map to [0;1] range by dividing by far_plane
  light_dist /= far_plane;

  // write this as modified depth
  gl_FragDepth = light_dist;
}
