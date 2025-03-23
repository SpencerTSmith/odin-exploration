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

PAD :: [4]byte

Point_Light :: struct #align(16){
  position:     vec3,
  _:PAD,

  color:       vec3,
  _:PAD,
  attenuation: vec3,

  intensity:   f32,
  ambient:     f32,
}

Direction_Light :: struct {
  direction:   vec3,
  _:PAD,

  color:       vec3,

  intensity:   f32,
  ambient:     f32,
}

Spot_Light :: struct {
  position:    vec3,
  _:PAD,
  direction:   vec3,
  _:PAD,

  color:       vec3,
  _:PAD,
  attenuation: vec3,

  intensity:   f32,
  ambient:     f32,

  // Cosines
  inner_cutoff:  f32,
  outer_cutoff:  f32,
}

Frame_Buffer :: struct {
  id:               u32,
  color_target: Texture,
  depth_target: Texture,
}

make_frame_buffer :: proc(width, height: int) -> (buffer: Frame_Buffer, ok: bool) {
  fbo: u32
  gl.CreateFramebuffers(1, &fbo)

  handles: [2]u32
  gl.CreateTextures(gl.TEXTURE_2D, 2, &handles[0])
  color := handles[0]
  depth := handles[1]
  gl.TextureStorage2D(color, 1, gl.RGBA8, i32(width), i32(height))
  gl.TextureStorage2D(depth, 1, gl.DEPTH24_STENCIL8, i32(width), i32(height))
  gl.NamedFramebufferTexture(fbo, gl.COLOR_ATTACHMENT0,         color, 0)
  gl.NamedFramebufferTexture(fbo, gl.DEPTH_STENCIL_ATTACHMENT,  depth, 0)

  if gl.CheckNamedFramebufferStatus(fbo, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
    fmt.println("Unable to create complete framebuffer")
    return
  }

  ok = true
  buffer = {
    id           = fbo,
    color_target = Texture(color),
    depth_target = Texture(depth),
  }
  return
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

Window :: struct {
  handle:   glfw.WindowHandle,
  w, h:     int,
  cursor_x: f64,
  cursor_y: f64,
  title:    string,
}

resize_window :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
  gl.Viewport(0, 0, width, height)
  window_struct := cast(^Window)glfw.GetWindowUserPointer(window)
  window_struct.w = int(width)
  window_struct.h = int(height)
}

get_aspect_ratio :: proc(window: Window) -> (aspect: f32) {
  aspect = f32(window.w) / f32(window.h)
  return
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

Screen_Quad :: struct {
  array:  Vertex_Array_Object,
  buffer: Vertex_Buffer,
}

SCREEN_QUAD_VERTICES :: []f32 {
  // position , uv
  -1.0,  1.0,  0.0, 1.0,
  -1.0, -1.0,  0.0, 0.0,
   1.0, -1.0,  1.0, 0.0,

  -1.0,  1.0,  0.0, 1.0,
   1.0, -1.0,  1.0, 0.0,
   1.0,  1.0,  1.0, 1.0
}

// TODO: May just want a little wrapper for batching up immediate mode type stuff
// Stuff like draw quad, draw line, etc
