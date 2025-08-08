package main

import "core:os"
import "core:log"
import "core:strings"
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

// TODO: Not sure I really like doing this, but I prefer having nice debug info
// If I wanted to do this in a nicer way, maybe I could do it like how I do the
// table for glfw input table
Uniform_Type :: enum i32 {
  F32  = gl.FLOAT,
  I32  = gl.INT,
  BOOL = gl.BOOL,

  VEC3 = gl.FLOAT_VEC3,
  VEC4 = gl.FLOAT_VEC4,

  MAT4 = gl.FLOAT_MAT4,

  SAMPLER_2D    = gl.SAMPLER_2D,
  SAMPLER_CUBE  = gl.SAMPLER_CUBE,
  SAMPLER_2D_MS = gl.SAMPLER_2D_MULTISAMPLE,

  SAMPLER_CUBE_ARRAY = gl.SAMPLER_CUBE_MAP_ARRAY,
}

Uniform :: struct {
  name:     string,
  type:     Uniform_Type,
  location: i32,
  size:     i32,
  binding:  i32,
}

Shader_Debug_Mode :: enum i32 {
  NONE  = 0,
  DEPTH = 1,
}

UBO_Bind :: enum u32 {
  FRAME = 0,
}

MAX_POINT_LIGHTS :: 128
Frame_UBO :: struct {
  projection:      mat4,
  orthographic:    mat4,
  view:            mat4,
  proj_view:       mat4,
  camera_position: vec4,
  z_near:          f32,
  z_far:           f32,
  debug_mode:      Shader_Debug_Mode, // i32 or glsl int
  scene_extents:   vec4,

  // Frame
  lights: struct {
    direction:    Direction_Light_Uniform,
    points:       [MAX_POINT_LIGHTS]Point_Light_Uniform,
    points_count: u32,
    spot:         Spot_Light_Uniform,
  },
}

make_shader_from_string :: proc(source: string, type: Shader_Type) -> (shader: Shader, ok: bool) {
  // Resolve all #includes
  // TODO: For now will not do recursive includes, but maybe won't be nessecary
  lines := strings.split_lines(source, context.temp_allocator)

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
          log.error("Couldn't read shader file: %s, for include", rel_path)
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
    log.error("Error compiling shader:\n%s\n", string(info[:]))
    log.error("%s", with_include)
    ok = false
    return
  }

  // NOTE: What errors could there be?
  ok = true
  return
}

make_shader_from_file :: proc(file_name: string, type: Shader_Type, prepend_common: bool = true) -> (shader: Shader, ok: bool) {
  rel_path := filepath.join({SHADER_DIR, file_name}, context.temp_allocator)

  source, file_ok := os.read_entire_file(rel_path, context.temp_allocator)
  if !file_ok {
    log.error("Couldn't read shader file: %s", rel_path)
    ok = false
    return
  }

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
    log.error("Error linking shader program:\n%s", string(info[:]))
    ok = false
    return
  }

  program.uniforms = make_shader_uniform_map(program, allocator = allocator)

  ok = true
  return program, ok
}

make_shader_uniform_map :: proc(program: Shader_Program, allocator := context.allocator) -> (uniforms: map[string]Uniform) {
  uniform_count: i32
  gl.GetProgramiv(program.id, gl.ACTIVE_UNIFORMS, &uniform_count)

  uniforms = make(map[string]Uniform, allocator = allocator)

  for i in 0..<uniform_count {
    uniform: Uniform
    len: i32
    name_buf: [256]byte // Surely no uniform name is going to be >256 chars

    type: u32
    gl.GetActiveUniform(program.id, u32(i), 256, &len, &uniform.size, &type, &name_buf[0])

    uniform.type = Uniform_Type(type)

    // Only collect uniforms not in blocks
    uniform.location = gl.GetUniformLocation(program.id, cstring(&name_buf[0]))
    if uniform.location != -1 {
      uniform.name = strings.clone(string(name_buf[:len])) // May just want to do fixed size

      // Check the initial binding point
      // NOTE: will be junk if not actually set in shader
      // TODO: should proably be more thorough in checking types that might have
      // binding
      if uniform.type == .SAMPLER_2D   ||
         uniform.type == .SAMPLER_CUBE ||
         uniform.type == .SAMPLER_2D_MS ||
         uniform.type == .SAMPLER_CUBE_ARRAY {
           gl.GetUniformiv(program.id, uniform.location, &uniform.binding);
      }

      uniforms[uniform.name] = uniform
    }
  }

  return uniforms
}

bind_shader :: proc(name: string) {
  assert(name in state.shaders)
  bind_shader_program(state.shaders[name])
}

bind_shader_program :: proc(program: Shader_Program) {
  if state.current_shader.id != program.id {
    gl.UseProgram(program.id)

    state.current_shader = program

    // FIXME: Nasty bug due to current architecture where if a model gets drawn and
    // the current shader doesn't have texture bindings for a material
    // those textures don't get bound BUT the current material does get set...
    // This fixes it but I'm not satisfied... gotta be nice way to check
    // if a shader supports a material, if not don't set the current material
    state.current_material = {}
  }
}

free_shader_program :: proc(program: ^Shader_Program) {
  gl.DeleteProgram(program.id)

  for _, uniform in program.uniforms {
    delete(uniform.name)
  }
  delete(program.uniforms)
}

set_shader_uniform :: proc(name: string, value: $T,
                                 program: Shader_Program = state.current_shader) {
  assert(state.current_shader.id == program.id)

  if name in program.uniforms {
    when T == i32 || T == int || T == bool{
      gl.Uniform1i(program.uniforms[name].location, i32(value))
    } else when T == f32 {
      gl.Uniform1f(program.uniforms[name].location, value)
    } else when T == vec3 {
      gl.Uniform3f(program.uniforms[name].location, value.x, value.y, value.z)
    } else when T == vec4 {
      gl.Uniform4f(program.uniforms[name].location, value.x, value.y, value.z, value.w)
    } else when T == mat4 {
      copy := value
      gl.UniformMatrix4fv(program.uniforms[name].location, 1, gl.FALSE, raw_data(&copy))
    } else when T == []mat4 {
      copy := value
      length := i32(len(value))
      assert(length <= program.uniforms[name].size)
      gl.UniformMatrix4fv(program.uniforms[name].location, length, gl.FALSE, raw_data(raw_data(copy)))
    } else {
	    log.warn("Unable to match type (%v) to gl call for uniform\n", typeid_of(T))
    }
  } else {
    // HACK: Need to think of nicer way to handle these situations
    // I would like to be alerted... but also annoying in some situations when prototyping
    // fmt.printf("Uniform (\"%v\") not in current shader (id = %v)\n", name, program.id)
  }
}
