package main

import "core:mem"
import gl "vendor:OpenGL"

// NOTE: This might end up being a needles abstraction layer
// But I would like a common interface for getting and writing to GPU buffers without worrying whether it is mapped or not

// NOTE: As well if the buffer is persistent it will TRIPLE buffer it
// To allow simultaneous writes to the same buffer used by multiple frames

GPU_Buffer_Type :: enum {
  NONE,
  UNIFORM,
  VERTEX,
}

GPU_Buffer :: struct {
  type:      GPU_Buffer_Type,
  id:        u32,
  mapped:    rawptr,
  item_size: int,
}

// TODO: look into metaprogramming stuff to automatically creat VAO from vertex structs
// make_vertex_buffer :: proc(vertex_struct: $T, size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
//   buffer = make_gpu_buffer(.VERTEX, size, data, persistent)
// }

// NOTE: right now not possible to get a buffer you can read from with this interface
make_gpu_buffer :: proc(type: GPU_Buffer_Type, size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
  buffer.type = type

  gl.CreateBuffers(1, &buffer.id)

  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT if persistent else 0

  gl.NamedBufferStorage(buffer.id, size, data, flags | gl.DYNAMIC_STORAGE_BIT)

  if persistent {
    buffer.mapped = gl.MapNamedBufferRange(buffer.id, 0, size, flags)
  }

  return buffer
}

// Only for uniform buffers
bind_gpu_buffer_base :: proc(buffer: GPU_Buffer, binding: UBO_Bind) {
  assert(buffer.type == .UNIFORM)
  gl.BindBufferBase(gl.UNIFORM_BUFFER, u32(binding), buffer.id)
}

// Only for uniform buffers, also handles alignment for ya
bind_gpu_buffer_range :: proc(buffer: GPU_Buffer, binding: u32, offset, size: int) {
  assert(buffer.type == .UNIFORM)

  // FIXME: Just save this in the state, instead of querying every time
  min_alignment: i32
  gl.GetIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, &min_alignment)

  aligned_offset := mem.align_forward_int(offset, int(min_alignment))

  gl.BindBufferRange(gl.UNIFORM_BUFFER, binding, buffer.id, aligned_offset, size)
}

write_gpu_buffer :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr, frame_index: int = state.frame_index) {
  if buffer.mapped != nil {
    ptr := uintptr(buffer.mapped) + uintptr(offset)
    mem.copy(rawptr(ptr), data, size)
  } else {
    gl.NamedBufferSubData(buffer.id, offset, size, data)
  }
}

free_gpu_buffer :: proc(buffer: ^GPU_Buffer) {
  if buffer.mapped != nil {
    gl.UnmapNamedBuffer(buffer.id)
  }
  gl.DeleteBuffers(1, &buffer.id)
}
