package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:math/linalg/glsl"
import "core:path/filepath"

import gl "vendor:OpenGL"
import "vendor:glfw"

// NOTE: For everything that doesn't have a home yet

RED   :: vec4{1.0, 0.0, 0.0,  1.0}
GREEN :: vec4{0.0, 1.0, 0.0,  1.0}
BLUE  :: vec4{0.0, 0.0, 1.0,  1.0}
CORAL :: vec4{1.0, 0.5, 0.31, 1.0}
BLACK :: vec4{0.0, 0.0, 0.0,  1.0}
WHITE :: vec4{1.0, 1.0, 1.0,  1.0}

LEARN_OPENGL_BLUE   :: vec4{0.2, 0.3, 0.3, 1.0}
LEARN_OPENGL_ORANGE :: vec4{1.0, 0.5, 0.2, 1.0}

BILLION :: 1_000_000_000

// Includes the separator
PATH_SLASH :: filepath.SEPARATOR_STRING

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4

dvec2 :: glsl.dvec2
dvec3 :: glsl.dvec3
dvec4 :: glsl.dvec4

mat4 :: glsl.mat4

// Adds a 0 to the end
vec4_from_3 :: proc(vec: vec3) -> vec4 {
  return {vec.x, vec.y, vec.z, 1.0}
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

resize_window :: proc() {
  // Reset
  state.window.resized = false

  ok: bool
  state.hdr_ms_buffer, ok = remake_framebuffer(&state.hdr_ms_buffer, state.window.w, state.window.h)
  state.post_buffer, ok = remake_framebuffer(&state.post_buffer, state.window.w, state.window.h)
  state.ping_pong_buffers[0], ok = remake_framebuffer(&state.ping_pong_buffers[0], state.window.w, state.window.h)
  state.ping_pong_buffers[1], ok = remake_framebuffer(&state.ping_pong_buffers[1], state.window.w, state.window.h)

  if !ok {
    log.fatal("Window has been resized but unable to recreate multisampling framebuffer")
    state.running = false
  }
}

Framebuffer :: struct {
  id:            u32,
  attachments:   []Framebuffer_Attachment,
  color_targets: []Texture,
  depth_target:  Texture,
  sample_count:  int,
}

Framebuffer_Attachment :: enum {
  COLOR,
  HDR_COLOR,
  DEPTH,
  DEPTH_STENCIL,
  DEPTH_CUBE,
  DEPTH_CUBE_ARRAY,
}

// For now depth target can either be depth only or depth+stencil,
// also can only have one attachment of each type
make_framebuffer :: proc(width, height: int, samples: int = 0, array_depth: int = 0,
                         attachments: []Framebuffer_Attachment = {.COLOR, .DEPTH_STENCIL}
                         ) -> (buffer: Framebuffer, ok: bool) {
  fbo: u32
  gl.CreateFramebuffers(1, &fbo)

  color_targets := make([dynamic]Texture, context.temp_allocator)
  depth_target: Texture

  gl_attachments := make([dynamic]u32, context.temp_allocator)

  for attachment in attachments {
    switch attachment {
    case .COLOR:
      color_target := alloc_texture(._2D, .RGBA8, .NONE, width, height, samples=samples)
      attachment := cast(u32) (gl.COLOR_ATTACHMENT0 + len(color_targets))
      gl.NamedFramebufferTexture(fbo,  attachment, color_target.id, 0)

      append(&color_targets, color_target)
      append(&gl_attachments, attachment)

    case .HDR_COLOR:
      color_target := alloc_texture(._2D, .RGBA16F, .NONE, width, height, samples=samples)
      attachment := cast(u32) (gl.COLOR_ATTACHMENT0 + len(color_targets))
      gl.NamedFramebufferTexture(fbo,  attachment, color_target.id, 0)

      append(&color_targets, color_target)
      append(&gl_attachments, attachment)

    case .DEPTH:
      assert(depth_target.id == 0) // Only one depth attachment

      depth_target = alloc_texture(._2D, .DEPTH32, .NONE, width, height)

      // Really for shadow mapping... but eh
      gl.TextureParameteri(depth_target.id, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
      gl.TextureParameteri(depth_target.id, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
      border_color := vec4{1.0, 1.0, 1.0, 1.0}
      gl.TextureParameterfv(depth_target.id, gl.TEXTURE_BORDER_COLOR, &border_color[0])

      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)

    case .DEPTH_STENCIL:
      assert(depth_target.id == 0)

      depth_target = alloc_texture(._2D, .DEPTH24_STENCIL8, .NONE, width, height, samples=samples)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)

    case .DEPTH_CUBE:
      assert(depth_target.id == 0)

      depth_target = alloc_texture(.CUBE, .DEPTH32, .CLAMP_LINEAR, width, height)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)

    case .DEPTH_CUBE_ARRAY:
      assert(depth_target.id == 0)

      assert(array_depth > 0)
      depth_target = alloc_texture(.CUBE_ARRAY, .DEPTH32, .CLAMP_LINEAR, width, height, array_depth=array_depth)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)
    }
  }

  gl.NamedFramebufferDrawBuffers(fbo, cast(i32)len(color_targets), raw_data(gl_attachments))

  buffer = {
    id            = fbo,
    attachments   = slice.clone(attachments, state.perm_alloc),
    color_targets = slice.clone(color_targets[:], state.perm_alloc),
    depth_target  = depth_target,
    sample_count  = samples,
  }
  if gl.CheckNamedFramebufferStatus(fbo, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
    log.error("Unable to create complete framebuffer: %v", buffer)
    return {}, false
  }

  ok = true
  return buffer, ok
}

bind_framebuffer :: proc(buffer: Framebuffer) {
  gl.BindFramebuffer(gl.FRAMEBUFFER, buffer.id)
}

free_framebuffer :: proc(frame_buffer: ^Framebuffer) {
  for &c in frame_buffer.color_targets {
    free_texture(&c)
  }
  free_texture(&frame_buffer.depth_target)
  gl.DeleteFramebuffers(1, &frame_buffer.id)
}

// Will use the same sample count as the old
remake_framebuffer :: proc(frame_buffer: ^Framebuffer, width, height: int) -> (new_buffer: Framebuffer, ok: bool) {
  old_samples     := frame_buffer.sample_count
  old_attachments := frame_buffer.attachments
  free_framebuffer(frame_buffer)
  new_buffer, ok = make_framebuffer(width, height, old_samples, attachments=old_attachments)
  log.info(new_buffer.attachments)

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

should_close :: proc() -> bool {
  return bool(glfw.WindowShouldClose(state.window.handle)) || !state.running
}

close_program :: proc() {
  state.running = false
}

draw_debug_stats :: proc() {
  template :=
`
FPS: %0.4v
Position: %0.4v
Yaw: %0.4v
Pitch: %0.4v
Fov: %0.4v
Point Lights: %v
`
  text := fmt.aprintf(template,
                      state.fps,
                      state.camera.position,
                      state.camera.yaw,
                      state.camera.pitch,
                      state.camera.curr_fov_y,
                      len(state.point_lights) if state.point_lights_on else 0,
                      allocator = context.temp_allocator)

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
