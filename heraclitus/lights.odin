package main

import "core:math"

Point_Light :: struct {
  position:    vec3,

  color:       vec4,

  radius:      f32,
  intensity:   f32,
  ambient:     f32,
}

Point_Light_Uniform :: struct #align(16) {
  proj_views:    [6]mat4,

  position:  vec4,

  color:     vec4,

  radius:    f32,
  intensity: f32,
  ambient:   f32,
}

Direction_Light :: struct {
  direction: vec3,

  color:     vec4,

  intensity: f32,
  ambient:   f32,
}

Direction_Light_Uniform :: struct #align(16) {
  proj_view: mat4,

  direction: vec4,

  color:     vec4,

  intensity: f32,
  ambient:   f32,
}

Spot_Light :: struct {
  position:     vec3,
  direction:    vec3,

  color:        vec4,

  radius:       f32,
  intensity:    f32,
  ambient:      f32,

  // Cosines
  inner_cutoff: f32,
  outer_cutoff: f32,
}

Spot_Light_Uniform :: struct #align(16) {
  position:     vec4,
  direction:    vec4,
  color:        vec4,

  radius:       f32,
  intensity:    f32,
  ambient:      f32,

  inner_cutoff: f32,
  outer_cutoff: f32,
}

spot_light_uniform :: proc(light: Spot_Light) -> (uniform: Spot_Light_Uniform) {
  uniform = Spot_Light_Uniform{
    position  = vec4_from_3(light.position),
    direction = vec4_from_3(light.direction),

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,

    inner_cutoff = light.inner_cutoff,
    outer_cutoff = light.outer_cutoff,
  }

  return uniform
}

point_light_uniform :: proc(light: Point_Light) -> (uniform: Point_Light_Uniform) {
  snapped := vec4{
    // math.floor(light.position.x / 0.5) * 0.5,
    light.position.x,
    light.position.y,
    light.position.z,
    // math.floor(light.position.y / 0.5) * 0.5,
    // math.floor(light.position.z / 0.5) * 0.5,
    1.0,
  }
  uniform = Point_Light_Uniform{
    proj_views = point_light_projviews(light),
    position   = snapped,

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}

direction_light_uniform :: proc(light: Direction_Light) -> (uniform: Direction_Light_Uniform) {
  scene_bounds: f32 = 50.0
  sun_distance: f32 = 75.0

  texel_size := (scene_bounds * 2.0) / f32(SUN_SHADOW_MAP_SIZE)

  center := state.camera.position

  // Snap to texel coords, heard this is quite good
  center.x = math.floor(center.x / texel_size) * texel_size
  center.z = math.floor(center.z / texel_size) * texel_size

  sun_position := center - (state.sun.direction * sun_distance)
  light_view := get_view(sun_position, state.sun.direction, CAMERA_UP)
  light_proj := get_orthographic(-scene_bounds, scene_bounds, -scene_bounds, scene_bounds, 1.0, sun_distance * 2.0)

  uniform = Direction_Light_Uniform{
    proj_view = light_proj * light_view,

    direction = vec4_from_3(light.direction),

    color     = light.color,

    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}

LIGHT_Z_NEAR :: f32(1.0)

// NOTE: Assumes the shadow CUBE map is a CUBE so 1:1 aspect ratio for each side
point_light_projviews :: proc(light: Point_Light) -> [6]mat4 {
  proj := get_perspective(90.0, 1.0, LIGHT_Z_NEAR, light.radius)
  projviews := [6]mat4{
    proj * get_view(light.position.xyz, { 1.0,  0.0,  0.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, {-1.0,  0.0,  0.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, { 0.0,  1.0,  0.0}, {0.0,  0.0,  1.0}),
    proj * get_view(light.position.xyz, { 0.0, -1.0,  0.0}, {0.0,  0.0, -1.0}),
    proj * get_view(light.position.xyz, { 0.0,  0.0,  1.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, { 0.0,  0.0, -1.0}, {0.0, -1.0,  0.0}),
  }

  return projviews
}
