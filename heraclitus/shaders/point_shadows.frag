#version 450 core

in VS_OUT {
  vec4 world_position;
  flat int  light_index;
} fs_in;

#include "include.glsl"

void main() {
  Point_Light light = frame.lights.points[fs_in.light_index];

  // get distance between fragment and light source
  float light_dist = length(fs_in.world_position.xyz - light.position.xyz);

  // map to [0;1] range by dividing by far_plane
  light_dist /= light.radius;

  // write this as modified depth
  gl_FragDepth = light_dist;
}
