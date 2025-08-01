package main

import "core:mem"
import gl "vendor:OpenGL"

GPU_Buffer_Type :: enum {
  NONE,
  UNIFORM,
  VERTEX,
}

GPU_Buffer :: struct {
  type:   GPU_Buffer_Type,
  id:     u32,
  mapped: rawptr,
}

make_gpu_buffer :: proc(size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: GPU_Buffer) {
  gl.CreateBuffers(1, &buffer.id)

  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT if persistent else 0

  gl.NamedBufferStorage(buffer.id, size, data, flags | gl.DYNAMIC_STORAGE_BIT)

  if persistent {
    buffer.mapped = gl.MapNamedBufferRange(buffer.id, 0, size, flags)
  }

  return buffer
}

bind_gpu_buffer_base :: proc(buffer: GPU_Buffer, binding: UBO_Bind) {
  gl.BindBufferBase(gl.UNIFORM_BUFFER, u32(binding), buffer.id)
}

bind_gpu_buffer_range :: proc(buffer: GPU_Buffer, binding: u32, offset, size: int) {
  gl.BindBufferRange(gl.UNIFORM_BUFFER, binding, buffer.id, offset, size)
}

write_gpu_buffer :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr) {
  if buffer.mapped != nil {
    mem.copy(buffer.mapped, data, size)
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
