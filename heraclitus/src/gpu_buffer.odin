package main

import "core:mem"
import "core:reflect"

import gl "vendor:OpenGL"

// NOTE: This might end up being a needless abstraction layer
// But I would like a common interface for getting and writing to GPU buffers without worrying whether it is mapped or not
// As well as writing to them, at the right index

// NOTE: As well if the buffer is persistent it WILL triple buffer it
// To allow writes to the same buffer used by multiple frames not to get stomped
// Basically: persistent == triple_buffered

GPU_Buffer_Type :: enum {
  NONE,
  UNIFORM,
  VERTEX,
}

// NOTE: Fat struct... too much voodoo?
GPU_Buffer :: struct {
  id:         u32,
  type:       GPU_Buffer_Type,
  mapped:     rawptr,
  total_size: int,

  range_size: int, // Frame range, aligned for you

  // Vertex specific stuff
  vao:          u32,
  item_size:    int,
  index_offset: int,
}

// Pass in a vertex struct get an VAO with automatic vertex attribs... metaprogramming hahaha
// NOTE: Still need to bind the vertex buffer to the vertex array... this just sets up attribs
// FIXME: Only really works if all members are float arrays
make_vertex_vao :: proc($vert_type: typeid) -> u32 {
  vao: u32
  gl.CreateVertexArrays(1, &vao)

  // Helper
  type_to_gl_type :: proc(id: typeid) -> (gl_type: u32) {
    switch id {
    case f32:
      gl_type = gl.FLOAT
    case f64:
      gl_type = gl.DOUBLE
    }

    return gl_type
  }

  type_info := type_info_of(vert_type)

  if reflect.is_struct(type_info) {
    field_count := reflect.struct_field_count(vert_type)

    for i in 0..<field_count {
      field := reflect.struct_field_at(vert_type, i)

      field_gl_type: u32
      field_length := 1

      if reflect.is_array(field.type) {
        array_type := field.type.variant.(reflect.Type_Info_Array)

        field_length = array_type.count
        field_gl_type = type_to_gl_type(array_type.elem.id)
      }

      gl.EnableVertexArrayAttrib(vao,  u32(i))
      gl.VertexArrayAttribFormat(vao,  u32(i), i32(field_length), field_gl_type, gl.FALSE, u32(field.offset))
      gl.VertexArrayAttribBinding(vao, u32(i), 0)
    }
  } else if reflect.is_array(type_info) {
    array_type := type_info.variant.(reflect.Type_Info_Array)

    field_gl_type := type_to_gl_type(array_type.elem.id)
    gl.EnableVertexArrayAttrib(vao,  0)
    gl.VertexArrayAttribFormat(vao,  0, i32(array_type.count), field_gl_type, gl.FALSE, 0)
    gl.VertexArrayAttribBinding(vao, 0, 0)
  }

  return vao
}

align_size_for_gpu :: proc(size: int) -> (aligned: int) {
  min_alignment: i32
  gl.GetIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, &min_alignment)

 aligned = mem.align_forward_int(size, int(min_alignment))
 return aligned
}

make_vertex_buffer :: proc($vertex_type: typeid, vertex_count: int, index_count: int = 0,
                           vertex_data: rawptr = nil, index_data: rawptr = nil, persistent: bool = false) -> (buffer: GPU_Buffer) {
  vao := make_vertex_vao(vertex_type)

  vertex_length := vertex_count * size_of(vertex_type)
  index_length  := index_count  * size_of(Mesh_Index) // FIXME: Hardcoded, but can't pass in compile time known arg defaults

  vertex_length_align := align_size_for_gpu(vertex_length)
  index_length_align  := align_size_for_gpu(index_length)

  total_size := vertex_length_align + index_length_align

  buffer = make_gpu_buffer(.VERTEX, total_size, vertex_data, persistent)
  buffer.item_size = size_of(vertex_type)
  buffer.vao = u32(vao)

  buffer.index_offset = vertex_length_align

  gl.VertexArrayVertexBuffer(u32(vao), 0, buffer.id, 0, i32(buffer.item_size))
  if index_count > 0 {
    gl.VertexArrayElementBuffer(u32(vao), buffer.id)
  }

  write_gpu_buffer(buffer, 0, vertex_length, vertex_data)
  write_gpu_buffer(buffer, buffer.index_offset, index_length, index_data)

  return buffer
}

bind_vertex_buffer :: proc(buffer: GPU_Buffer) {
  assert(buffer.type == .VERTEX, "Buffer must be of type vertex")
  assert(buffer.vao != 0, "Must have valid vao")

  gl.BindVertexArray(buffer.vao)
}

unbind_vertex_buffer :: proc() {
  gl.BindVertexArray(0);
}

// NOTE: right now not possible to get a buffer you can read from with this interface
make_gpu_buffer :: proc(type: GPU_Buffer_Type, size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
  assert(state.gl_is_initialized)
  buffer.type = type

  gl.CreateBuffers(1, &buffer.id)

  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT if persistent else 0

  buffer.range_size  = align_size_for_gpu(size)
  buffer.total_size = buffer.range_size * FRAMES_IN_FLIGHT if persistent else buffer.range_size

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
  if data != nil {
    if buffer.mapped != nil {
      ptr := uintptr(buffer.mapped) + uintptr(offset)
      mem.copy(rawptr(ptr), data, size)
    } else {
      gl.NamedBufferSubData(buffer.id, offset, size, data)
    }
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
gpu_buffer_frame_offset :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> int {
  assert(frame_index < FRAMES_IN_FLIGHT && frame_index >= 0)
  frame_offset := buffer.range_size * frame_index

  return frame_offset
}

bind_gpu_buffer_frame_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, frame_index: int = state.curr_frame_index) {
  frame_offset := gpu_buffer_frame_offset(buffer, frame_index)

  bind_gpu_buffer_range(buffer, binding, frame_offset, buffer.range_size)
}

write_gpu_buffer_frame :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr, frame_index: int = state.curr_frame_index) {
  assert(size <= buffer.range_size)

  frame_offset := gpu_buffer_frame_offset(buffer, frame_index)

  write_gpu_buffer(buffer, frame_offset + offset, size, data)
}

gpu_buffer_frame_base_ptr :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> rawptr {
  frame_offset := gpu_buffer_frame_offset(buffer, frame_index)

  address := uintptr(buffer.mapped) + uintptr(frame_offset)

  return rawptr(address)
}

free_gpu_buffer :: proc(buffer: ^GPU_Buffer) {
  if buffer.mapped != nil {
    gl.UnmapNamedBuffer(buffer.id)
  }
  gl.DeleteBuffers(1, &buffer.id)
}
