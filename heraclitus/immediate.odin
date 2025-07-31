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

immediate_vertex :: proc(xy: vec2, rgba: vec4 = WHITE, uv: vec2 = {0.0, 0.0}) {
  assert(state.immediate.vertex_mapped != nil, "Uninitialized Immediate State")

  if state.immediate.vertex_count >= MAX_IMMEDIATE_VERTEX_COUNT {
    fmt.eprintf("Too many immediate vertices, flushing before next vertex")
    immediate_flush()
  }

  vertex := Immediate_Vertex{
    position = xy,
    uv       = uv,
    color    = rgba,
  }

  state.immediate.vertex_mapped[state.immediate.vertex_count] = vertex
  state.immediate.vertex_count += 1
}

immediate_quad :: proc(xy: vec2, w, h: f32, rgba: vec4 = WHITE,
                       uv0: vec2 = {0.0, 0.0}, uv1: vec2 = {0.0, 0.0},
                       texture: Texture = state.immediate.white_texture) {
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

  // TODO: Maybe consider index buffer too?
  immediate_vertex(top_left.position, top_left.color, top_left.uv)
  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)

  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_right.position, bottom_right.color, bottom_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)
}

immediate_flush :: proc() {
  if state.immediate.vertex_count > 0 {
    bind_shader_program(state.immediate.shader)
    bind_texture(state.immediate.curr_texture, 0)
    set_shader_uniform("tex",  0)

    gl.BindVertexArray(u32(state.immediate.vertex_array))
    defer gl.BindVertexArray(0);

    gl.DrawArrays(gl.TRIANGLES, 0, i32(state.immediate.vertex_count))
    // FIXME: TERRIBLE! triple buffer or proper sync
    gl.Finish()

    // And reset
    state.immediate.vertex_count = 0
  }
}
