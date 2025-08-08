package main

import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"

CAMERA_UP :: vec3{0.0, 1.0, 0.0}

Camera :: struct {
  position:   vec3,
  move_speed: f32,

  yaw, pitch:  f32, // Degrees
  sensitivity: f32,

  curr_fov_y:    f32, // Degrees
  target_fov_y:  f32, // Degrees
}

update_camera :: proc(camera: ^Camera, dt_s: f64) {
  dt_s := f32(dt_s)

  CAMERA_ZOOM_SPEED :: 10.0
  camera.curr_fov_y = glsl.lerp(camera.curr_fov_y, camera.target_fov_y, CAMERA_ZOOM_SPEED * dt_s)
}

get_camera_view :: proc(camera: Camera) -> (view: mat4) {
  forward := get_camera_forward(camera)
  // the target is the camera position + the forward direction
  return get_view(camera.position, forward, CAMERA_UP)
}

get_view :: proc(position, forward, up: vec3) -> (view: mat4) {
  return glsl.mat4LookAt(position, forward + position, up)
}

// Returns normalized
get_camera_forward :: proc(camera: Camera) -> (forward: vec3) {
  using camera
  rad_yaw   := glsl.radians_f32(yaw)
  rad_pitch := glsl.radians_f32(pitch)
  forward = {
    -math.cos(rad_pitch) * math.cos(rad_yaw),
    math.sin(rad_pitch),
    math.cos(rad_pitch) * math.sin(rad_yaw),
  }
  forward = linalg.normalize0(forward)

  return forward
}

get_camera_perspective :: proc(camera: Camera, aspect_ratio, z_near, z_far: f32) -> (perspective: mat4){
  return get_perspective(camera.curr_fov_y, aspect_ratio, z_near, z_far)
}

// Fov in degrees
get_perspective :: proc(fov_y, aspect_ratio, z_near, z_far: f32) -> (perspective: mat4) {
  return glsl.mat4Perspective(glsl.radians(fov_y), aspect_ratio, z_near, z_far)
}

// Ehh this can go here
get_orthographic :: proc(left, right, bottom, top, z_near, z_far: f32) -> (orthographic: mat4) {
 return glsl.mat4Ortho3d(left, right, bottom, top, z_near, z_far);
}

get_camera_axes :: proc(camera: Camera) -> (forward, up, right: vec3) {
  forward = get_camera_forward(camera)
  up = CAMERA_UP
  right = linalg.normalize(glsl.cross(forward, up))
  return forward, up, right
}
