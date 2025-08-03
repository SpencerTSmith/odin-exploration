package main

import "core:mem"
import "core:fmt"
import "core:reflect"

import gl "vendor:OpenGL"

// NOTE: This might end up being a needless abstraction layer
// But I would like a common interface for getting and writing to GPU buffers without worrying whether it is mapped or not
// As well as writing to them, at the right index

// NOTE: As well if the buffer is persistent it WILL triple buffer it
// To allow writes to the same buffer used by multiple frames not to get stomped
// Basically: persistent == triple_buffered

// TODO: Look into ssbo with vertex pulling... might simplify some of this metaprogramming logic?

Vertex_Array_Object :: distinct u32
Vertex_Buffer       :: distinct u32

GPU_Buffer_Type :: enum {
  NONE,
  UNIFORM,
  VERTEX,
}

GPU_Buffer :: struct {
  id:         u32,
  type:       GPU_Buffer_Type,
  mapped:     rawptr,
  total_size: int,

  range_size: int, // Aligned for you

  vao_id:     u32,
  item_size:  int,
}

// Pass in a vertex struct get an VAO with automatic vertex attribs... metaprogramming hahaha
// NOTE: Still need to bind the vertex buffer to the vertex array... this just sets up attribs
// FIXME: Only really works if all members are float arrays
make_vertex_vao :: proc($vert_struct: typeid) -> Vertex_Array_Object {
  vao: u32
  gl.CreateVertexArrays(1, &vao)

  field_count := reflect.struct_field_count(vert_struct)

  for i in 0..<field_count {
    field := reflect.struct_field_at(vert_struct, i)

    field_gl_type: u32
    field_length := 1

    if reflect.is_array(field.type) {
      array_type := field.type.variant.(reflect.Type_Info_Array)

      field_length = array_type.count
      switch array_type.elem.id {
      case f32:
        field_gl_type = gl.FLOAT
      case f64:
        field_gl_type = gl.DOUBLE
      }
    }

    gl.EnableVertexArrayAttrib(vao,  u32(i))
    gl.VertexArrayAttribFormat(vao,  u32(i), i32(field_length), field_gl_type, gl.FALSE, u32(field.offset))
    gl.VertexArrayAttribBinding(vao, u32(i), 0)
  }

  return Vertex_Array_Object(vao)
}

// TODO: look into metaprogramming stuff to automatically creat VAO from vertex structs
make_vertex_buffer :: proc($vertex_struct: typeid, vertex_count: int,
                           data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
  vao := make_vertex_vao(vertex_struct)

  size := size_of(vertex_struct) * vertex_count
  buffer = make_gpu_buffer(.VERTEX, size, data, persistent)
  buffer.item_size = size_of(vertex_struct)
  buffer.vao_id = u32(vao)
  gl.VertexArrayVertexBuffer(u32(vao), 0, buffer.id, 0, i32(buffer.item_size))

  return buffer
}

// NOTE: right now not possible to get a buffer you can read from with this interface
make_gpu_buffer :: proc(type: GPU_Buffer_Type, size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
  buffer.type = type

  gl.CreateBuffers(1, &buffer.id)

  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT if persistent else 0

  // FIXME: Just save this in the state, instead of querying every time
  min_alignment: i32
  gl.GetIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, &min_alignment)

  buffer.range_size  = mem.align_forward_int(size, int(min_alignment))
  buffer.total_size = buffer.range_size * FRAMES_IN_FLIGHT if persistent else buffer.range_size

  // fmt.printf("Item size: %v, Aligned size: %v, Total size: %v\n", size, buffer.range_size, buffer.total_size)

  gl.NamedBufferStorage(buffer.id, buffer.total_size, data, flags | gl.DYNAMIC_STORAGE_BIT)

  if persistent {
    buffer.mapped = gl.MapNamedBufferRange(buffer.id, 0, buffer.total_size, flags)
  }

  if !persistent {
    assert(buffer.total_size == buffer.range_size)
  }

  return buffer
}

gpu_buffer_is_mapped :: proc(buffer: GPU_Buffer) -> bool {
  return buffer.mapped != nil
}

write_gpu_buffer :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr) {
  if buffer.mapped != nil {
    ptr := uintptr(buffer.mapped) + uintptr(offset)
    mem.copy(rawptr(ptr), data, size)
  } else {
    gl.NamedBufferSubData(buffer.id, offset, size, data)
  }
}

// Only for uniform buffers
bind_gpu_buffer_base :: proc(buffer: GPU_Buffer, binding: UBO_Bind) {
  assert(buffer.type == .UNIFORM)
  gl.BindBufferBase(gl.UNIFORM_BUFFER, u32(binding), buffer.id)
}

// Only for uniform buffers
bind_gpu_buffer_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, offset, size: int) {
  assert(buffer.type == .UNIFORM)

  gl.BindBufferRange(gl.UNIFORM_BUFFER, u32(binding), buffer.id, offset, size)
}

// Helper fast paths for triple buffered frame dependent buffers
calc_gpu_buffer_frame_offset :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> int {
  assert(frame_index < FRAMES_IN_FLIGHT && frame_index >= 0)
  frame_offset := buffer.range_size * frame_index

  return frame_offset
}

bind_gpu_buffer_frame_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, frame_index: int = state.curr_frame_index) {
  frame_offset := calc_gpu_buffer_frame_offset(buffer, frame_index)

  bind_gpu_buffer_range(buffer, binding, frame_offset, buffer.range_size)
}

write_gpu_buffer_frame :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr, frame_index: int = state.curr_frame_index) {
  assert(size <= buffer.range_size)

  frame_offset := calc_gpu_buffer_frame_offset(buffer, frame_index)

  write_gpu_buffer(buffer, frame_offset + offset, size, data)
}

free_gpu_buffer :: proc(buffer: ^GPU_Buffer) {
  if buffer.mapped != nil {
    gl.UnmapNamedBuffer(buffer.id)
  }
  gl.DeleteBuffers(1, &buffer.id)
}
