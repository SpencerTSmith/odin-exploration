package main

import "core:fmt"

import gl "vendor:OpenGL"

MAX_IMMEDIATE_VERTEX_COUNT :: 4096

Immediate_Vertex :: struct {
  position: vec2,
  uv:       vec2,
  color:    vec4,
}

Immediate_State :: struct {
  vertex_buffer: GPU_Buffer,
  vertex_count:  int,

  // This tracks the index from which a flush starts
  flush_base:   int,

  shader:        Shader_Program,
  white_texture: Texture,
  curr_texture:  Texture,
}

// "Singleton" in c++ terms, but less stupid
@(private="file")
immediate: Immediate_State

init_immediate_renderer :: proc() -> (ok: bool) {
  max_size   := size_of(Immediate_Vertex) * MAX_IMMEDIATE_VERTEX_COUNT
  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT

  vertex_buffer := make_vertex_buffer(Immediate_Vertex, MAX_IMMEDIATE_VERTEX_COUNT, nil, persistent=true)

  shader := make_shader_program("immediate.vert", "immediate.frag", state.perm_alloc) or_return

  immediate = {
    vertex_buffer = vertex_buffer,
    vertex_count  = 0,
    shader        = shader,
  }

  immediate.white_texture, ok = make_texture("white.png")
  immediate.curr_texture = immediate.white_texture

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

free_immediate_renderer :: proc() {
  free_gpu_buffer(&immediate.vertex_buffer)
  free_shader_program(&immediate.shader)
}

immediate_vertex :: proc(xy: vec2, rgba: vec4 = WHITE, uv: vec2 = {0.0, 0.0}) {
  assert(gpu_buffer_is_mapped(immediate.vertex_buffer), "Uninitialized Immediate State")

  if immediate_total_verts() >= MAX_IMMEDIATE_VERTEX_COUNT {
    fmt.eprintf("Too many (%v) immediate vertices!!!!!!\n", immediate_total_verts())
  }

  vertex := Immediate_Vertex{
    position = xy,
    uv       = uv,
    color    = rgba,
  }

  item_size := immediate.vertex_buffer.item_size
  offset    := item_size * (immediate.vertex_count + immediate.flush_base)

  write_gpu_buffer_frame(immediate.vertex_buffer, offset, item_size, &vertex)
  immediate.vertex_count += 1
}

immediate_quad :: proc(xy: vec2, w, h: f32, rgba: vec4 = WHITE,
                       uv0: vec2 = {0.0, 0.0}, uv1: vec2 = {0.0, 0.0},
                       texture: Texture = immediate.white_texture) {
  immediate_set_texture(texture)

  top_left := Immediate_Vertex{
    position = xy,
    uv       = uv0,
    color    = rgba,
  }
  top_right := Immediate_Vertex{
    position = {xy.x + w, xy.y},
    uv       = {uv1.x, uv0.y},
    color    = rgba,
  }
  bottom_left := Immediate_Vertex{
    position = {xy.x,     xy.y + h},
    uv       = {uv0.x, uv1.y},
    color    = rgba,
  }
  bottom_right := Immediate_Vertex{
    position = {xy.x + w, xy.y + h},
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

immediate_flush :: proc() {
  if immediate.vertex_count > 0 {
    bind_shader_program(immediate.shader)
    bind_texture(immediate.curr_texture, 0)
    set_shader_uniform("tex",  0)

    gl.BindVertexArray(immediate.vertex_buffer.vao_id)
    defer gl.BindVertexArray(0);

    frame_index := calc_gpu_buffer_frame_offset(immediate.vertex_buffer) / immediate.vertex_buffer.item_size
    first_index := frame_index + immediate.flush_base // Add the last flush

    gl.DrawArrays(gl.TRIANGLES, i32(first_index), i32(immediate.vertex_count))

    // And reset
    immediate.flush_base += immediate.vertex_count
    immediate.vertex_count = 0
  }
}
