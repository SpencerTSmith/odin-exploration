package main

import "core:log"
import "core:math"
import "core:math/linalg"

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
  uniform = Point_Light_Uniform{
    proj_views = point_light_projviews(light),
    position   = vec4_from_3(light.position),

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}

@(private)
prev_center: vec3

direction_light_uniform :: proc(light: Direction_Light) -> (uniform: Direction_Light_Uniform) {
  scene_bounds: f32 = 50.0
  sun_distance: f32 = 50.0

  center := state.camera.position

  // FIXME: Just a hack to prevent shadow swimming until i can unstick my head out of my ass and figure
  // out the texel snapping shit
  if linalg.length(center - prev_center) < 10.0 {
    center = prev_center
  }

  prev_center = center

  light_proj := get_orthographic(-scene_bounds, scene_bounds, -scene_bounds, scene_bounds, 5.0, sun_distance * 2.0)

  sun_position := center - (light.direction * sun_distance)
  light_view := get_look_at(sun_position, center, CAMERA_UP)

  //
  // frustum_corners := [8]vec4{
  //   // Far
  //   {-1.0,  1.0,  1.0, 1}, // top left
  //   { 1.0,  1.0,  1.0, 1}, // top right
  //   { 1.0, -1.0,  1.0, 1}, // bottom right
  //   {-1.0, -1.0,  1.0, 1}, // bottom left
  //   // Near
  //   {-1.0,  1.0, -1.0, 1}, // top left
  //   { 1.0,  1.0, -1.0, 1}, // top right
  //   { 1.0, -1.0, -1.0, 1}, // bottom right
  //   {-1.0, -1.0, -1.0, 1}, // bottom left
  // }
  //
  // cam_view := get_camera_view(state.camera)
  // cam_proj := get_camera_perspective(state.camera, 100)
  // cam_view_proj := cam_proj * cam_view
  // inv_cam       := linalg.inverse(cam_view_proj)
  //
  // world_corners: [8]vec4
  //
  // for corner, idx in frustum_corners {
  //   world_pos := inv_cam * corner
  //   world_pos /= world_pos.w
  //
  //   world_corners[idx] = world_pos
  //   // log.info(world_pos)
  // }
  //
  // light_view := get_look_at({0,0,0}, light.direction, CAMERA_UP)
  //
  // min_x, max_x := max(f32), min(f32)
  // min_y, max_y := max(f32), min(f32)
  // min_z, max_z := max(f32), min(f32)
  //
  // for corner in world_corners {
  //   light_space_pos := light_view * corner
  //   log.info(light_space_pos)
  //
  //   min_x = math.min(min_x, light_space_pos.x)
  //   max_x = math.max(max_x, light_space_pos.x)
  //   min_y = math.min(min_y, light_space_pos.y)
  //   max_y = math.max(max_y, light_space_pos.y)
  //   min_z = math.min(min_z, light_space_pos.z)
  //   max_z = math.max(max_z, light_space_pos.z)
  // }
  //
  // light_proj := get_orthographic(min_x, max_x, min_y, max_y, 0.1, max_z - min_z)

  uniform = Direction_Light_Uniform {
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
