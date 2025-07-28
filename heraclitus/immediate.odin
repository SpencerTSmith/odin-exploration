package main

import "core:fmt"

import gl "vendor:OpenGL"

MAX_IMMEDIATE_VERTEX_COUNT :: 2056

Immediate_Vertex :: struct {
  position: vec2,
  uv:       vec2,
  color:    vec4,
}

Immediate_State :: struct {
  vertex_array:  Vertex_Array_Object,
  vertex_buffer: Vertex_Buffer,
  vertex_mapped: [^]Immediate_Vertex,
  vertex_count:  int,

  shader:        Shader_Program,
  white_texture: Texture,
  curr_texture:  Texture,
}

init_immediate_renderer :: proc() -> (ok: bool) {
  max_size   := size_of(Immediate_Vertex) * MAX_IMMEDIATE_VERTEX_COUNT
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
  // position: vec2
  gl.EnableVertexArrayAttrib(vao,  1)
  gl.VertexArrayAttribFormat(vao,  1, len(vertex.uv), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.uv)))
  gl.VertexArrayAttribBinding(vao, 1, 0)
  // color: vec4
  gl.EnableVertexArrayAttrib(vao,  2)
  gl.VertexArrayAttribFormat(vao,  2, len(vertex.color), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.color)))
  gl.VertexArrayAttribBinding(vao, 2, 0)

  shader := make_shader_program("immediate.vert", "immediate.frag", state.perm_alloc) or_return

  state.immediate = {
    vertex_array  = Vertex_Array_Object(vao),
    vertex_buffer = Vertex_Buffer(vbo),
    vertex_mapped = ([^]Immediate_Vertex)(mapped),
    vertex_count  = 0,
    shader        = shader,
  }

  state.immediate.white_texture, ok = make_texture("./assets/white.png")
  state.immediate.curr_texture = state.immediate.white_texture

  return ok
}

immediate_set_texture :: proc(texture: Texture) {
  if state.immediate.curr_texture.id != texture.id {
    immediate_flush()
    state.immediate.curr_texture = texture
  }
}

free_immediate_renderer :: proc() {
  gl.DeleteBuffers(1, cast(^u32)&state.immediate.vertex_buffer);
  gl.DeleteVertexArrays(1, cast(^u32)&state.immediate.vertex_array);
  free_shader_program(&state.immediate.shader)
}

immediate_vertex :: proc {
  immediate_vertex_direct,
  immediate_vertex_color_texture,
  immediate_vertex_texture,
  immediate_vertex_color,
}

immediate_vertex_direct :: proc(vertex: Immediate_Vertex) {
  assert(state.immediate.vertex_mapped != nil, "Uninitialized UI State")

  if state.immediate.vertex_count >= MAX_IMMEDIATE_VERTEX_COUNT {
    fmt.eprintf("Too many immediate vertices, flushing before next vertex")
    immediate_flush()
  }

  state.immediate.vertex_mapped[state.immediate.vertex_count] = vertex
  state.immediate.vertex_count += 1
}

immediate_vertex_color_texture :: proc(xy, uv: vec2, rgba: vec4) {
  vertex := Immediate_Vertex{
    position = xy,
    uv       = uv,
    color    = rgba,
  }

  immediate_vertex_direct(vertex)
}

immediate_vertex_texture :: proc(xy, uv: vec2) {
  vertex := Immediate_Vertex{
    position = xy,
    uv       = uv,
    color    = {1.0, 1.0, 1.0, 1.0},
  }

  immediate_vertex_direct(vertex)
}

immediate_vertex_color :: proc(xy: vec2, rgba: vec4) {
  vertex := Immediate_Vertex{
    position = xy,
    color    = rgba,
  }

  immediate_vertex_direct(vertex)
}

immediate_quad :: proc {
  immediate_quad_vertex,
  immediate_quad_texture,
  immediate_quad_color_no_alpha,
  immediate_quad_color_alpha,
}

immediate_quad_vertex :: proc(top_left, top_right, bottom_left, bottom_right: Immediate_Vertex) {
  immediate_vertex(top_left)
  immediate_vertex(top_right)
  immediate_vertex(bottom_left)

  immediate_vertex(top_right)
  immediate_vertex(bottom_right)
  immediate_vertex(bottom_left)
}

immediate_quad_texture :: proc(xy: vec2, w, h: f32, uv0, uv1: vec2) {
  top_left := Immediate_Vertex{
    position = xy,
    uv       = uv0,
    color    = {1.0, 1.0, 1.0, 1.0},
  }
  top_right := Immediate_Vertex{
    position = {xy.x + w, xy.y},
    uv       = {uv1.x, uv0.y},
    color    = {1.0, 1.0, 1.0, 1.0},
  }
  bottom_left := Immediate_Vertex{
    position = {xy.x,     xy.y + h},
    uv       = {uv0.x, uv1.y},
    color    = {1.0, 1.0, 1.0, 1.0},
  }
  bottom_right := Immediate_Vertex{
    position = {xy.x + w, xy.y + h},
    uv       = uv1,
    color    = {1.0, 1.0, 1.0, 1.0},
  }

  immediate_quad(top_left, top_right, bottom_left, bottom_right)
}

immediate_quad_color_no_alpha :: proc(xy: vec2, w, h: f32, rgb: vec3) {
  rgba := vec4{rgb.r, rgb.g, rgb.b, 1.0}
  immediate_quad(xy, w, h, rgba)
}

immediate_quad_color_alpha :: proc(xy: vec2, w, h: f32, rgba: vec4) {
  top_left := Immediate_Vertex{
    position = xy,
    color    = rgba,
  }
  top_right := Immediate_Vertex{
    position = {xy.x + w, xy.y},
    color    = rgba,
  }
  bottom_left := Immediate_Vertex{
    position = {xy.x,     xy.y + h},
    color    = rgba,
  }
  bottom_right := Immediate_Vertex{
    position = {xy.x + w, xy.y + h},
    color    = rgba,
  }

  immediate_quad(top_left, top_right, bottom_left, bottom_right)
}


immediate_flush :: proc() {
  if state.immediate.vertex_count > 0 {
    bind_shader_program(state.immediate.shader)
    bind_texture(state.immediate.curr_texture, 0)
    set_shader_uniform(state.current_shader, "tex",  0)

    gl.BindVertexArray(u32(state.immediate.vertex_array))
    defer gl.BindVertexArray(0);

    gl.DrawArrays(gl.TRIANGLES, 0, i32(state.immediate.vertex_count))
    // FIXME: TERRIBLE! triple buffer or proper sync
    gl.Finish()

    // And reset
    state.immediate.vertex_count = 0
  }
}
