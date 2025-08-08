package main

AABB :: struct {
  min: vec3,
  max: vec3,
}

draw_aabb :: proc(aabb: AABB) {
  immediate_quad(aabb.min.xy, aabb.max.x, aabb.max.y, BLUE)
}
