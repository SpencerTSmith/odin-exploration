package main

import "core:log"

import gl "vendor:OpenGL"

MAX_IMMEDIATE_VERTEX_COUNT :: 4096

Immediate_Vertex :: struct {
  position: vec3,
  uv:       vec2,
  color:    vec4,
}

// NOTE: When an immediate_* function takes in a vec2 for position it usually means its in screen coords
// When taking in a vec3 for position its in world space

Immediate_Mode :: enum {
  TRIANGLES,
  LINES,
}

Immediate_Space :: enum {
  SCREEN,
  WORLD,
}

// NOTE: This is not integrated with the general asset system and deals with actual textures and such...
Immediate_State :: struct {
  vertex_buffer: GPU_Buffer,
  vertex_count:  int,

  // This tracks the index from which a flush starts
  flush_base:   int,

  shader:        Shader_Program,
  white_texture: Texture,

  curr_mode:     Immediate_Mode,
  curr_texture:  Texture,
  curr_space:    Immediate_Space,
}

// "Singleton" in c++ terms, but less stupid
// @(private="file")
immediate: Immediate_State

init_immediate_renderer :: proc() -> (ok: bool) {
  assert(state.gl_is_initialized)

  vertex_buffer := make_vertex_buffer(Immediate_Vertex, MAX_IMMEDIATE_VERTEX_COUNT, persistent = true)

  shader := make_shader_program("immediate.vert", "immediate.frag", state.perm_alloc) or_return

  immediate = {
    vertex_buffer = vertex_buffer,
    vertex_count  = 0,
    shader        = shader,
  }

  white_tex_handle: Texture_Handle
  white_tex_handle, ok = load_texture("white.png")

  immediate.white_texture = get_texture(white_tex_handle)^
  immediate.curr_texture  = immediate.white_texture

  return ok
}

immediate_total_verts :: proc() -> int {
  return immediate.flush_base + immediate.vertex_count
}

immediate_frame_reset :: proc() {
  immediate_flush()
  immediate.flush_base = 0
}

immediate_set_texture :: proc(texture: Texture) {
  if immediate.curr_texture.id != texture.id {
    immediate_flush()
    immediate.curr_texture = texture
  }
}

immediate_set_mode :: proc(mode: Immediate_Mode) {
  if immediate.curr_mode != mode {
    immediate_flush()
  }
  immediate.curr_mode = mode
}

immediate_set_space :: proc(space: Immediate_Space) {
  if immediate.curr_space != space {
    immediate_flush()
  }
  immediate.curr_space = space
}

free_immediate_renderer :: proc() {
  free_gpu_buffer(&immediate.vertex_buffer)
  free_shader_program(&immediate.shader)
}

immediate_vertex :: proc(xyz: vec3, rgba: vec4 = WHITE, uv: vec2 = {0.0, 0.0}) {
  assert(state.gl_is_initialized)
  assert(gpu_buffer_is_mapped(immediate.vertex_buffer), "Uninitialized Immediate State")

  if immediate_total_verts() >= MAX_IMMEDIATE_VERTEX_COUNT {
    log.error("Too many (%v) immediate vertices!!!!!!\n", immediate_total_verts())
    return
  }

  vertex := Immediate_Vertex{
    position = xyz,
    uv       = uv,
    color    = rgba,
  }

  vertex_ptr := cast([^]Immediate_Vertex)gpu_buffer_frame_base_ptr(immediate.vertex_buffer)
  offset     := immediate.vertex_count + immediate.flush_base

  vertex_ptr[offset] = vertex
  immediate.vertex_count += 1
}

// NOTE: A quad so takes in screen coordinates!
immediate_quad :: proc(xy: vec2, w, h: f32, rgba: vec4 = WHITE,
                       uv0: vec2 = {0.0, 0.0}, uv1: vec2 = {0.0, 0.0},
                       texture: Texture = immediate.white_texture) {

  immediate_set_texture(texture)
  immediate_set_mode(.TRIANGLES)
  immediate_set_space(.SCREEN)

  top_left := Immediate_Vertex{
    position = {xy.x, xy.y, -state.z_near},
    uv       = uv0,
    color    = rgba,
  }
  top_right := Immediate_Vertex{
    position = {xy.x + w, xy.y, -state.z_near},
    uv       = {uv1.x, uv0.y},
    color    = rgba,
  }
  bottom_left := Immediate_Vertex{
    position = {xy.x, xy.y + h, -state.z_near},
    uv       = {uv0.x, uv1.y},
    color    = rgba,
  }
  bottom_right := Immediate_Vertex{
    position = {xy.x + w, xy.y + h, -state.z_near},
    uv       = uv1,
    color    = rgba,
  }

  immediate_vertex(top_left.position, top_left.color, top_left.uv)
  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)

  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_right.position, bottom_right.color, bottom_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)
}

immediate_line :: proc {
  immediate_line_2D,
  immediate_line_3D,
}

// NOTE: A 2d line so takes in screen coordinates!
immediate_line_2D :: proc(xy0, xy1: vec2, rgba: vec4 = WHITE) {
  immediate_set_texture(immediate.white_texture)
  immediate_set_mode(.LINES)
  immediate_set_space(.SCREEN)

  immediate_vertex({xy0.x, xy0.y, -state.z_near}, rgba = rgba)
  immediate_vertex({xy1.x, xy1.y, -state.z_near}, rgba = rgba)
}

// NOTE: 3d line
immediate_line_3D :: proc(xyz0, xyz1: vec3, rgba: vec4 = WHITE) {

  immediate_set_texture(immediate.white_texture)

  immediate_set_mode(.LINES)
  immediate_set_space(.WORLD)

  immediate_vertex(xyz0, rgba = rgba)
  immediate_vertex(xyz1, rgba = rgba)
}

immediate_flush :: proc() {
  if immediate.vertex_count > 0 {
    bind_shader_program(immediate.shader)

    bind_texture(immediate.curr_texture, "tex")

    switch immediate.curr_space {
    case .SCREEN:
      set_shader_uniform("transform", get_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far))
    case .WORLD:
      set_shader_uniform("transform", get_camera_perspective(state.camera) * get_camera_view(state.camera))
    }

    bind_vertex_buffer(immediate.vertex_buffer)
    defer unbind_vertex_buffer()

    frame_index  := gpu_buffer_frame_offset(immediate.vertex_buffer) / immediate.vertex_buffer.item_size
    first_vertex := frame_index + immediate.flush_base // Add the last flush

    switch immediate.curr_mode {
    case .TRIANGLES:
      gl.DrawArrays(gl.TRIANGLES, i32(first_vertex), i32(immediate.vertex_count))
    case .LINES:
      gl.DrawArrays(gl.LINES, i32(first_vertex), i32(immediate.vertex_count))
    }

    // And reset, pushing the base up
    immediate.flush_base += immediate.vertex_count
    immediate.vertex_count = 0
  }
}
