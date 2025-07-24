package main

import "core:fmt"

import gl "vendor:OpenGL"

MAX_UI_VERTEX_COUNT :: 1024

Immediate_Vertex :: struct {
  position: vec2,
  color:    vec4,
}

Immediate_State :: struct {
  vertex_array:  Vertex_Array_Object,
  vertex_buffer: Vertex_Buffer,
  vertex_mapped: [^]Immediate_Vertex,
  vertex_count:  int,

  shader:        Shader_Program
}

make_immediate_renderer :: proc() -> (ui: Immediate_State, ok: bool) {
  max_size   := size_of(Immediate_Vertex) * MAX_UI_VERTEX_COUNT
  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT

  vbo: u32
  gl.CreateBuffers(1, &vbo)
  gl.NamedBufferStorage(vbo, max_size, nil, flags | gl.DYNAMIC_STORAGE_BIT)
  mapped := gl.MapNamedBufferRange(vbo, 0, max_size, flags)

  vao: u32
  gl.CreateVertexArrays(1, &vao)
  gl.VertexArrayVertexBuffer(vao, 0, vbo, 0, size_of(Immediate_Vertex))

  vertex: Immediate_Vertex
  // position: vec2
  gl.EnableVertexArrayAttrib(vao,  0)
  gl.VertexArrayAttribFormat(vao,  0, len(vertex.position), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.position)))
  gl.VertexArrayAttribBinding(vao, 0, 0)
  // color: vec4
  gl.EnableVertexArrayAttrib(vao,  1)
  gl.VertexArrayAttribFormat(vao,  1, len(vertex.color), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.color)))
  gl.VertexArrayAttribBinding(vao, 1, 0)

  shader := make_shader_program("ui.vert", "ui.frag") or_return

  ui = {
    vertex_array  = Vertex_Array_Object(vao),
    vertex_buffer = Vertex_Buffer(vbo),
    vertex_mapped = ([^]Immediate_Vertex)(mapped),
    vertex_count  = 0,
    shader        = shader,
  }

  return ui, true
}

immediate_vertex :: proc(xy: vec2, rgba: vec4) {
  assert(state.ui.vertex_mapped != nil, "Uninitialized UI State")

  if state.ui.vertex_count >= MAX_UI_VERTEX_COUNT {
    fmt.eprintf("Too many ui vertices")
  }

  state.ui.vertex_mapped[state.ui.vertex_count] = { position = xy, color = rgba}
  state.ui.vertex_count += 1
}

immediate_quad :: proc {
  immediate_quad_no_alpha,
  immediate_quad_alpha,
}

immediate_quad_no_alpha :: proc(xy: vec2, w, h: f32, rgb: vec3) {
  rgba := vec4{rgb.r, rgb.g, rgb.b, 1.0}
  immediate_quad(xy, w, h, rgba)
}

immediate_quad_alpha :: proc(xy: vec2, w, h: f32, rgba: vec4) {
  top_left     := xy
  top_right    := vec2{xy.x + w, xy.y}
  bottom_left  := vec2{xy.x,     xy.y + h}
  bottom_right := vec2{xy.x + w, xy.y + h}

  immediate_vertex(top_left, rgba)
  immediate_vertex(top_right, rgba)
  immediate_vertex(bottom_left, rgba)

  immediate_vertex(top_right, rgba)
  immediate_vertex(bottom_right, rgba)
  immediate_vertex(bottom_left, rgba)
}

immediate_flush :: proc() {
  bind_shader_program(state.ui.shader)

  gl.BindVertexArray(u32(state.ui.vertex_array))
  defer gl.BindVertexArray(0);

  gl.DrawArrays(gl.TRIANGLES, 0, i32(state.ui.vertex_count))

  // And reset
  state.ui.vertex_count = 0
}
