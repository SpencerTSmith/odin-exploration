package main

import gl "vendor:OpenGL"
import "core:math/linalg/glsl"

AABB :: struct {
  min: vec3,
  max: vec3,
}


aabb_corners :: proc(aabb: AABB) -> [8]vec3 {
  min := aabb.min
  max := aabb.max
  corners := [8]vec3{
    {min.x, min.y, min.z}, // left, bottom, back
    {max.x, min.y, min.z}, // right, bottom, back
    {max.x, max.y, min.z}, // right, top, back
    {min.x, max.y, min.z}, // left, top, back
    {min.x, max.y, max.z}, // left, top, front
    {min.x, min.y, max.z}, // left, bottom, front
    {max.x, min.y, max.z}, // right, bottom, front
    {max.x, max.y, max.z}, // right, top, front
  }

  return corners
}

aabb_minkowski_difference :: proc(a: AABB, b: AABB) -> AABB {
  result: AABB = {
    min = a.min - b.max,
    max = a.max - b.min,
  }

  return result
}

transform_aabb :: proc {
  transform_aabb_matrix,
  transform_aabb_components,
  transform_aabb_no_rotate,
}

transform_aabb_matrix :: proc(aabb: AABB, transform: mat4) -> AABB {
  corners := aabb_corners(aabb)

  for &c in corners {
    c = (transform * vec4_from_3(c)).xyz
  }

  min_v := vec3{max(f32), max(f32), max(f32)}
  max_v := vec3{min(f32), min(f32), min(f32)}

  for c in corners {
    min_v = glsl.min(min_v, c)
    max_v = glsl.max(max_v, c)
  }

  recalc: AABB = {
    min = min_v,
    max = max_v,
  }

  return recalc
}

transform_aabb_components :: proc(aabb: AABB, translation, rotation, scale: vec3) -> AABB {
  translation_mat := glsl.mat4Translate(translation)
  scale_mat       := glsl.mat4Scale(scale)

  return transform_aabb_matrix(aabb, translation_mat * scale_mat)
}

transform_aabb_no_rotate :: proc(aabb: AABB, translation, scale: vec3) -> AABB {
  return transform_aabb_components(aabb, translation, {0,0,0}, scale)
}

aabbs_intersect :: proc(a: AABB, b: AABB) -> bool {
  intersects := (a.min.x <= b.max.x && a.max.x >= b.min.x) &&
                (a.min.y <= b.max.y && a.max.y >= b.min.y) &&
                (a.min.z <= b.max.z && a.max.z >= b.min.z)

  return intersects
}

aabb_intersect_point :: proc(a: AABB, p: vec3) -> bool {
  intersects := (a.min.x <= p.x && a.max.x >= p.x) &&
                (a.min.y <= p.y && a.max.y >= p.y) &&
                (a.min.z <= p.z && a.max.z >= p.z)

  return intersects
}

draw_aabb :: proc(aabb: AABB, color: vec4 = GREEN) {
  corners := aabb_corners(aabb)

  // Back
  immediate_line(corners[0], corners[1], color)
  immediate_line(corners[1], corners[2], color)
  immediate_line(corners[2], corners[3], color)
  immediate_line(corners[3], corners[0], color)

  // Front
  immediate_line(corners[4], corners[5], color)
  immediate_line(corners[5], corners[6], color)
  immediate_line(corners[6], corners[7], color)
  immediate_line(corners[7], corners[4], color)

  // Left
  immediate_line(corners[4], corners[3], color)
  immediate_line(corners[5], corners[0], color)

  // Right
  immediate_line(corners[7], corners[2], color)
  immediate_line(corners[6], corners[1], color)

  immediate_flush()
}
