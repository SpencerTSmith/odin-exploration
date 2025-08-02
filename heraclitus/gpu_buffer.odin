package main

import "core:mem"
import "core:fmt"

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

GPU_Buffer :: struct {
  id:         u32,
  type:       GPU_Buffer_Type,
  mapped:     rawptr,
  total_size: int,
  range_size: int, // Aligned for you
}

// TODO: look into metaprogramming stuff to automatically creat VAO from vertex structs
make_vertex_buffer :: proc(vertex_struct: $T, size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
  buffer = make_gpu_buffer(.VERTEX, size, data, persistent)
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

  fmt.printf("Item size: %v, Aligned size: %v, Total size: %v\n", size, buffer.range_size, buffer.total_size)

  gl.NamedBufferStorage(buffer.id, buffer.total_size, data, flags | gl.DYNAMIC_STORAGE_BIT)

  if persistent {
    buffer.mapped = gl.MapNamedBufferRange(buffer.id, 0, buffer.total_size, flags)
  }

  return buffer
}

write_gpu_buffer :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr) {
  fmt.printf("Writing GPU_Buffer at range %v, %v\n", offset, offset + size)

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

  fmt.printf("Binding %v at range %v, %v\n", binding, offset, offset + size)

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

  write_gpu_buffer(buffer, frame_offset, size, data)
}

free_gpu_buffer :: proc(buffer: ^GPU_Buffer) {
  if buffer.mapped != nil {
    gl.UnmapNamedBuffer(buffer.id)
  }
  gl.DeleteBuffers(1, &buffer.id)
}
