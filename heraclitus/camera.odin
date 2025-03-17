package main

import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"

import "core:fmt"

CAMERA_UP :: vec3{0.0, 1.0, 0.0}

Camera :: struct {
  position:     vec3,
  yaw, pitch:   f32,
  move_speed:   f32,
  sensitivity: f32,
  fov_y:       f32,
}

get_camera_view :: proc(camera: Camera) -> (view: mat4) {
  forward := get_camera_forward(camera)
  // the target is the camera position + the forward direction
  return glsl.mat4LookAt(camera.position, forward + camera.position, CAMERA_UP)
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

  return
}

get_camera_perspective :: proc(camera: Camera, aspect_ratio, z_near, z_far: f32) -> (projection: mat4){
  return glsl.mat4Perspective(camera.fov_y, aspect_ratio, z_near, z_far)
}

get_camera_axes :: proc(camera: Camera) -> (forward, up, right: vec3) {
  forward = get_camera_forward(camera)
  up = CAMERA_UP
  right = linalg.normalize(glsl.cross(forward, up))
  return
}
