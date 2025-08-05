package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:path/filepath"

import gl "vendor:OpenGL"
import "vendor:glfw"

// NOTE: For everything that doesn't have a home yet

RED   :: vec4{1.0, 0.0, 0.0,  1.0}
CORAL :: vec4{1.0, 0.5, 0.31, 1.0}
BLACK :: vec4{0.0, 0.0, 0.0,  1.0}
WHITE :: vec4{1.0, 1.0, 1.0,  1.0}

LEARN_OPENGL_BLUE   :: vec4{0.2, 0.3, 0.3, 1.0}
LEARN_OPENGL_ORANGE :: vec4{1.0, 0.5, 0.2, 1.0}

BILLION :: 1_000_000_000

// Includes the separator
PATH_SLASH :: filepath.SEPARATOR_STRING
DATA_DIR :: "data" + PATH_SLASH

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

squared_distance :: proc(a_pos: vec3, b_pos: vec3) -> f32 {
  dx := a_pos.x - b_pos.x
  dy := a_pos.y - b_pos.y
  dz := a_pos.z - b_pos.z

  return dx * dx + dy * dy + dz * dz
}

point_in_rect :: proc(point: vec2, left, top, bottom, right: f32) -> bool {
  return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
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

Window :: struct {
  handle:   glfw.WindowHandle,
  w, h:     int,
  title:    string,
  resized:  bool,
}

resize_window_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
  gl.Viewport(0, 0, width, height)
  state_struct := cast(^State)glfw.GetWindowUserPointer(window)
  state_struct.window.w = int(width)
  state_struct.window.h = int(height)
  state_struct.window.resized = true
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

close_program :: proc() {
  state.running = false
}

toggle_debug_stats :: proc() {
  state.draw_debug_stats = !state.draw_debug_stats
}

draw_debug_stats :: proc() {
  template :=
`
FPS: %0.4v
Position: %0.4v
Yaw: %0.4v
Pitch: %0.4v
Fov: %0.4v
`
  text := fmt.aprintf(template, state.fps, state.camera.position, state.camera.yaw, state.camera.pitch, state.camera.curr_fov_y, allocator = context.temp_allocator)

  x := f32(state.window.w) * 0.0125
  y := f32(state.window.h) * 0.0125

  BOX_COLOR :: vec4{0.0, 0.0, 0.0, 0.7}
  BOX_PAD   :: 10.0
  box_width, box_height := text_draw_size(text, state.default_font)

  // HACK: Just looks a bit better to me, not going to work with all fonts probably
  box_height -= state.default_font.line_height * 0.5

  immediate_quad({x - BOX_PAD, y - BOX_PAD}, box_width + BOX_PAD * 2, box_height + BOX_PAD, BOX_COLOR)

  draw_text(text, state.default_font, x, y)
}
