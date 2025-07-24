package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:mem"
import "core:path/filepath"

import gl "vendor:OpenGL"

SHADER_DIR :: "shaders"

Shader_Type :: enum u32 {
  VERT = gl.VERTEX_SHADER,
  FRAG = gl.FRAGMENT_SHADER,
}

Shader :: distinct u32

Shader_Program :: struct {
  id:       u32,
  uniforms: map[string]Uniform,
}

Uniform_Type :: enum i32 {
  F32  = gl.FLOAT,
  F64  = gl.DOUBLE,
  I32  = gl.INT,
  BOOL = gl.BOOL,
}

Uniform :: struct {
  location: i32,
  size:     i32,
  type:     Uniform_Type,
  name:     string,
}

Uniform_Buffer :: struct {
  id:     u32,
  mapped: rawptr,
}

UBO_Bind :: enum u32 {
  FRAME = 0,
  LIGHT = 1,
}

Shader_Debug_Mode :: enum i32 {
  NONE  = 0,
  DEPTH = 1,
}

Frame_UBO :: struct {
  projection:      mat4,
  orthographic:    mat4,
  view:            mat4,
  camera_position: vec4,
  z_near:          f32,
  z_far:           f32,
  debug_mode:      Shader_Debug_Mode, // i32 or glsl int
  scene_extents:   vec4,
}

MAX_POINT_LIGHTS :: 16
Light_UBO :: struct #min_field_align(16) {
  direction:    Direction_Light,
  points:       [MAX_POINT_LIGHTS]Point_Light,
  points_count: u32,
  spot:         Spot_Light,
}

make_shader_from_string :: proc(source: string, type: Shader_Type, prepend_common: bool = true) -> (shader: Shader, ok: bool) {
  // Resolve all #includes
  // TODO: For now will not do recursive includes, but maybe won't be nessecary
  lines := strings.split_lines(source, context.temp_allocator)
  defer free_all(context.temp_allocator)

  include_builder := strings.builder_make_none(context.temp_allocator)
  for line in lines {
    trim := strings.trim_space(line)
    if strings.starts_with(trim, "#include") {
      first := strings.index(trim, "\"")
      last  := strings.last_index(trim, "\"")

      if first != -1 && last > first {
        file     := trim[first + 1:last]
        rel_path := filepath.join({SHADER_DIR, file}, context.temp_allocator)

        include_code, file_ok := os.read_entire_file(rel_path, context.temp_allocator)
        if !file_ok {
          fmt.eprintln("Couldn't read shader file: %s, for include", rel_path)
          ok = false
          return
        }

        strings.write_string(&include_builder, string(include_code))
      }
    } else {
      strings.write_string(&include_builder, line)
      strings.write_string(&include_builder, "\n")
    }
  }

  with_include := strings.to_string(include_builder)

  c_str     := strings.clone_to_cstring(with_include, allocator = context.temp_allocator)
  c_str_len := i32(len(with_include))

  shader =  Shader(gl.CreateShader(u32(type)))
  gl.ShaderSource(u32(shader), 1, &c_str, &c_str_len)
  gl.CompileShader(u32(shader))

  success: i32
  gl.GetShaderiv(u32(shader), gl.COMPILE_STATUS, &success)
  if success == 0 {
    info: [512]u8
    gl.GetShaderInfoLog(u32(shader), 512, nil, &info[0])
    fmt.eprintf("Error compiling shader:\n%s\n", string(info[:]))
    ok = false
    return
  }

  // TODO(ss): actually check for errors
  ok = true
  return
}

make_shader_from_file :: proc(file_name: string, type: Shader_Type, prepend_common: bool = true) -> (shader: Shader, ok: bool) {
  rel_path := filepath.join({SHADER_DIR, file_name}, context.temp_allocator)

  source, file_ok := os.read_entire_file(rel_path, context.temp_allocator)
  if !file_ok {
    fmt.eprintln("Couldn't read shader file: %s", rel_path)
    ok = false
    return
  }
  defer free_all(context.temp_allocator) // Don't need to keep this around

  shader, ok = make_shader_from_string(string(source), type)
  return
}

free_shader :: proc(shader: Shader) {
  gl.DeleteShader(u32(shader))
}

make_shader_program :: proc(vert_path, frag_path: string, allocator := context.allocator) -> (program: Shader_Program, ok: bool) {
  vert := make_shader_from_file(vert_path, .VERT) or_return
  defer free_shader(vert)
  frag := make_shader_from_file(frag_path, .FRAG) or_return
  defer free_shader(frag)

  program.id   = gl.CreateProgram()
  gl.AttachShader(program.id, u32(vert))
  gl.AttachShader(program.id, u32(frag))
  gl.LinkProgram(program.id)

  success: i32
  gl.GetProgramiv(program.id, gl.LINK_STATUS, &success)
  if success == 0 {
    info: [512]u8
    gl.GetProgramInfoLog(program.id, 512, nil, &info[0])
    fmt.eprintf("Error linking shader program:\n%s", string(info[:]))
    ok = false
    return
  }

  program.uniforms = make_shader_uniform_map(program, allocator = allocator)

  ok = true
  return
}

make_shader_uniform_map :: proc(program: Shader_Program, allocator := context.allocator) -> (uniforms: map[string]Uniform) {
  uniform_count: i32
  gl.GetProgramiv(program.id, gl.ACTIVE_UNIFORMS, &uniform_count)

  uniforms = make(map[string]Uniform, allocator = allocator)

  for i in 0..<uniform_count {
    uniform: Uniform
    len: i32
    name_buf: [256]byte // Surely no uniform name is going to be >256 chars

    gl.GetActiveUniform(program.id, u32(i), 256, &len, &uniform.size, cast(^u32)&uniform.type, &name_buf[0])

    // Only collect uniforms not in blocks
    uniform.location = gl.GetUniformLocation(program.id, cstring(&name_buf[0]))
    if uniform.location != -1 {
      uniform.name = strings.clone(string(name_buf[:len])) // May just want to do fixed size

      uniforms[uniform.name] = uniform
    }
  }
  return
}

bind_shader_program :: proc(program: Shader_Program) {
  if state.current_shader.id != program.id {
    gl.UseProgram(program.id)

    state.current_shader = program
  }
}

free_shader_program :: proc(program: ^Shader_Program) {
  gl.DeleteProgram(program.id)

  for _, uniform in program.uniforms {
    delete(uniform.name)
  }
  delete(program.uniforms)
}

set_shader_uniform :: proc {
  set_shader_uniform_i32,
  set_shader_uniform_f32,
  set_shader_uniform_b,
  set_shader_uniform_mat4,
  set_shader_uniform_vec3,
}

set_shader_uniform_i32 :: proc(program: Shader_Program, name: string, value: i32) {
  assert(state.current_shader.id == program.id)
  if name in program.uniforms {
    gl.Uniform1i(program.uniforms[name].location, value)
  } else {
    fmt.eprintf("Unable to set uniform \"%s\"\n", name)
  }
}

set_shader_uniform_b :: proc(program: Shader_Program, name: string, value: bool) {
  assert(state.current_shader.id == program.id)
  if name in program.uniforms {
    gl.Uniform1i(program.uniforms[name].location, i32(value))
  } else {
    fmt.eprintf("Unable to set uniform \"%s\"\n", name)
  }
}

set_shader_uniform_f32 :: proc(program: Shader_Program, name: string, value: f32) {
  assert(state.current_shader.id == program.id)
  if name in program.uniforms {
    gl.Uniform1f(program.uniforms[name].location, value)
  } else {
    fmt.eprintf("Unable to set uniform \"%s\"\n", name)
  }
}

set_shader_uniform_mat4 :: proc(program: Shader_Program, name: string, value: mat4) {
  assert(state.current_shader.id == program.id)
  copy := value
  if name in program.uniforms {
    gl.UniformMatrix4fv(program.uniforms[name].location, 1, gl.FALSE, raw_data(&copy))
  } else {
    fmt.eprintf("Unable to set uniform \"%s\"\n", name)
  }
}

set_shader_uniform_vec3 :: proc(program: Shader_Program, name: string, value: vec3) {
  assert(state.current_shader.id == program.id)
  if name in program.uniforms {
    gl.Uniform3f(program.uniforms[name].location, value.x, value.y, value.z)
  } else {
    fmt.eprintf("Unable to set uniform \"%s\"\n", name)
  }
}

make_uniform_buffer :: proc(size: int, data: rawptr = nil, persistent: bool = true) -> (buffer: Uniform_Buffer) {
  gl.CreateBuffers(1, &buffer.id)

  flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT if persistent else 0

  gl.NamedBufferStorage(buffer.id, size, data, flags | gl.DYNAMIC_STORAGE_BIT)

  if persistent {
    buffer.mapped = gl.MapNamedBufferRange(buffer.id, 0, size, flags)
  }

  return
}

bind_uniform_buffer_base :: proc(buffer: Uniform_Buffer, binding: UBO_Bind) {
  gl.BindBufferBase(gl.UNIFORM_BUFFER, u32(binding), buffer.id)
}

bind_uniform_buffer_range :: proc(buffer: Uniform_Buffer, binding: u32, offset, size: int) {
  gl.BindBufferRange(gl.UNIFORM_BUFFER, binding, buffer.id, offset, size)
}

write_uniform_buffer :: proc(buffer: Uniform_Buffer, offset, size: int, data: rawptr) {
  if buffer.mapped != nil {
    mem.copy(buffer.mapped, data, size)
  } else {
    gl.NamedBufferSubData(buffer.id, offset, size, data)
  }
}

free_uniform_buffer :: proc(buffer: ^Uniform_Buffer) {
  if buffer.mapped != nil {
    gl.UnmapNamedBuffer(buffer.id)
  }
  gl.DeleteBuffers(1, &buffer.id)
}
