package main

Point_Light :: struct {
  position:    vec3,

  color:       vec4,

  radius:      f32,
  intensity:   f32,
  ambient:     f32,
}

Point_Light_Uniform :: struct #align(16) {
  position:  vec4,

  color:     vec4,

  radius:    f32,
  intensity: f32,
  ambient:   f32,
}

Direction_Light :: struct {
  direction:   vec3,

  color:       vec4,

  intensity:   f32,
  ambient:     f32,
}

Direction_Light_Uniform :: struct #align(16) {
  direction:   vec4,

  color:       vec4,

  intensity:   f32,
  ambient:     f32,
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
    position  = vec4_from_3(light.position),

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}


direction_light_uniform :: proc(light: Direction_Light) -> (uniform: Direction_Light_Uniform) {
  uniform = Direction_Light_Uniform{
    direction = vec4_from_3(light.direction),

    color     = light.color,

    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}

LIGHT_Z_NEAR :: f32(0.001)

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
