package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"

import gl "vendor:OpenGL"
import "vendor:glfw"

// NOTE: For everything that doesn't have a home yet

CORAL :: vec3{1.0, 0.5, 0.31}
BLACK :: vec3{0.0, 0.0, 0.0}
WHITE :: vec3{1.0, 1.0, 1.0}

LEARN_OPENGL_BLUE :: vec3{0.2, 0.3, 0.3}
LEARN_OPENGL_ORANGE :: vec3{1.0, 0.5, 0.2}

BILLION :: 1_000_000_000

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4

dvec2 :: glsl.dvec2
dvec3 :: glsl.dvec3
dvec4 :: glsl.dvec4

mat4 :: glsl.mat4

// Adds a 0 to the end
vec4_from_3 :: proc(vec: vec3) -> vec4 {
  return {vec.x, vec.y, vec.z, 0.0}
}

Entity :: struct {
  position:  vec3,
  scale:    vec3,
  rotation: vec3,

  model:    ^Model,
}

// yxz euler angle
get_entity_model_mat4 :: proc(entity: Entity) -> (model: mat4) {
  translation := glsl.mat4Translate(entity.position)
  rotation_y := glsl.mat4Rotate({0.0, 1.0, 0.0}, glsl.radians_f32(entity.rotation.y))
  rotation_x := glsl.mat4Rotate({1.0, 0.0, 0.0}, glsl.radians_f32(entity.rotation.x))
  rotation_z := glsl.mat4Rotate({0.0, 0.0, 1.0}, glsl.radians_f32(entity.rotation.z))
  scale := glsl.mat4Scale(entity.scale)

  model = translation * rotation_y * rotation_x * rotation_z * scale
  return
}

// Attenuation = {x = constant, y = linear, z = quadratic}
Point_Light :: struct #align(16) {
  position:    vec4,

  color:       vec4,
  attenuation: vec4,

  intensity:   f32,
  ambient:     f32,
}

Direction_Light :: struct #align(16) {
  direction:   vec4,

  color:       vec4,

  intensity:   f32,
  ambient:     f32,
}

Spot_Light :: struct #align(16) {
  position:     vec4,
  direction:    vec4,

  color:        vec4,
  attenuation:  vec4,

  intensity:    f32,
  ambient:      f32,

  // Cosines
  inner_cutoff: f32,
  outer_cutoff: f32,
}

Framebuffer :: struct {
  id:            u32,
  color_target:  Texture,
  depth_target:  Texture,
  samples_count: int,
}

Framebuffer_Attachment :: enum {
  COLOR,
  DEPTH,
  DEPTH_STENCIL,
  DEPTH_CUBE,
}

// For now depth target can either be depth only or depth+stencil,
// also can only have one attachment of each type
make_framebuffer :: proc(width, height, samples: int,
                         attachments: []Framebuffer_Attachment = {.COLOR, .DEPTH_STENCIL}
                         ) -> (buffer: Framebuffer, ok: bool) {
  fbo: u32
  gl.CreateFramebuffers(1, &fbo)

  color_target, depth_target: Texture
  for attachment in attachments {
    switch attachment {
    case .COLOR:
      color_target = alloc_texture(width, height, .RGBA8, samples)
      gl.NamedFramebufferTexture(fbo, gl.COLOR_ATTACHMENT0, color_target.id, 0)
    case .DEPTH:
      depth_target = alloc_texture(width, height, .DEPTH, samples)
      gl.TextureParameteri(depth_target.id, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
      gl.TextureParameteri(depth_target.id, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
      border_color := vec4{1.0, 1.0, 1.0, 1.0}
      gl.TextureParameterfv(depth_target.id, gl.TEXTURE_BORDER_COLOR, &border_color[0])
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)
    case .DEPTH_STENCIL:
      depth_target = alloc_texture(width, height, .DEPTH_STENCIL, samples)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)
    case .DEPTH_CUBE:
      depth_target = alloc_texture_depth_cube(width, height)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)
    }
  }

  if gl.CheckNamedFramebufferStatus(fbo, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
    fmt.println("Unable to create complete framebuffer")
    return {}, false
  }

  ok = true
  buffer = {
    id            = fbo,
    color_target  = color_target,
    depth_target  = depth_target,
    samples_count = samples
  }
  return buffer, ok
}

free_framebuffer :: proc(frame_buffer: ^Framebuffer) {
  free_texture(&frame_buffer.color_target)
  free_texture(&frame_buffer.depth_target)
  gl.DeleteFramebuffers(1, &frame_buffer.id)
}

// Will use the same sample count as the old
remake_framebuffer :: proc(frame_buffer: ^Framebuffer, width, height: int) -> (new_buffer: Framebuffer, ok: bool) {
  old_sample_count := frame_buffer.samples_count
  free_framebuffer(frame_buffer)
  new_buffer, ok = make_framebuffer(width, height, old_sample_count)

  return new_buffer, ok
}

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

  return forward
}

get_camera_perspective :: proc(camera: Camera, aspect_ratio, z_near, z_far: f32) -> (projection: mat4){
  return glsl.mat4Perspective(camera.fov_y, aspect_ratio, z_near, z_far)
}

get_camera_axes :: proc(camera: Camera) -> (forward, up, right: vec3) {
  forward = get_camera_forward(camera)
  up = CAMERA_UP
  right = linalg.normalize(glsl.cross(forward, up))
  return forward, up, right
}

Window :: struct {
  handle:   glfw.WindowHandle,
  w, h:     int,
  cursor_x: f64,
  cursor_y: f64,
  title:    string,
  resized:  bool,
}

resize_window :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
  gl.Viewport(0, 0, width, height)
  window_struct := cast(^Window)glfw.GetWindowUserPointer(window)
  window_struct.w = int(width)
  window_struct.h = int(height)
  window_struct.resized = true
}

get_aspect_ratio :: proc(window: Window) -> (aspect: f32) {
  aspect = f32(window.w) / f32(window.h)
  return aspect
}

update_window_title_fps_dt :: proc(window: Window, fps, dt_s: f64) {
  buffer: [512]u8
  fmt.bprintf(buffer[:], "%s FPS: %f, DT: %f", window.title, fps, dt_s)
  c_str := cstring(raw_data(buffer[:]))
  glfw.SetWindowTitle(window.handle, c_str)
}

should_close :: proc() -> bool {
  return bool(glfw.WindowShouldClose(state.window.handle)) || !state.running
}
