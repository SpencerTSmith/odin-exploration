package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:mem"

import gl "vendor:OpenGL"

// I think these will be helpful for catching bugs, enforcing typing on all handles

Shader_Type :: enum u32 {
	VERT = gl.VERTEX_SHADER,
	FRAG = gl.FRAGMENT_SHADER,
}

Shader :: distinct u32

Uniform_Type :: enum i32 {
	F32 = gl.FLOAT,
	F64 = gl.DOUBLE,
	I32 = gl.INT,
	BOOL = gl.BOOL,
}

Uniform :: struct {
	location: i32,
	size:			i32,
	type:			Uniform_Type,
	name:			string,
}

Uniform_Map :: distinct map[string]Uniform

Shader_Program :: struct {
	id:				 u32,
	uniforms:	 Uniform_Map,
	allocator: mem.Allocator, // How was this allocated? Track this so we can check if this was heap allocated, If so, then we need to free the map along with the glTexture
}

make_shader_from_string :: proc(source: string, type: Shader_Type) -> (shader: Shader, ok: bool) {
	shader = Shader(gl.CreateShader(u32(type)))
	source_ptr := strings.unsafe_string_to_cstring(source)
	length := i32(len(source))

	gl.ShaderSource(u32(shader), 1, &source_ptr, &length)
	gl.CompileShader(u32(shader))

	success: i32
	gl.GetShaderiv(u32(shader), gl.COMPILE_STATUS, &success)
	if success == 0 {
		info: [512]u8
		gl.GetShaderInfoLog(u32(shader), 512, nil, &info[0])
		fmt.eprintf("Error compiling shader:\n%s", string(info[:]))
		ok = false
		return
	}

	// TODO(ss): actually check for errors
	ok = true
	return
}

make_shader_from_file :: proc(file_path: string, type: Shader_Type) -> (shader: Shader, ok: bool) {
	source, file_ok := os.read_entire_file(file_path, context.temp_allocator)
	if !file_ok {
		fmt.eprintln("Couldn't read shader file: %s", file_path)
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

	program.id = gl.CreateProgram()
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

	program.uniforms = make_shader_uniform_map(program, allocator)
	program.allocator = allocator

	ok = true
	return
}

make_shader_uniform_map :: proc(program: Shader_Program, allocator := context.allocator) -> (uniforms: Uniform_Map) {
	uniform_count: i32
	gl.GetProgramiv(program.id, gl.ACTIVE_UNIFORMS, &uniform_count)

	reserve(&uniforms, uniform_count)

	for i in 0..<uniform_count {
		uniform: Uniform
		len: i32
		name_buf: [256]u8 // Surely no uniform is going to be >256 chars

		gl.GetActiveUniform(program.id, u32(i), 256, &len, &uniform.size, cast(^u32)&uniform.type, &name_buf[0])

		uniform.location = gl.GetUniformLocation(program.id, cstring(&name_buf[0]))
		uniform.name = strings.clone(string(name_buf[:len])) // May just want to do fixed size

		uniforms[uniform.name] = uniform
	}

	return
}

use_shader_program :: proc(program: Shader_Program) {
	gl.UseProgram(program.id)
}

free_shader_program :: proc(program: Shader_Program) {
	gl.DeleteProgram(program.id)

	// If uni map was allocated on the heap, free it
	if program.allocator == context.allocator {
		for _, uniform in program.uniforms {
			delete(uniform.name)
		}
		delete(program.uniforms)
	}
}

set_shader_uniform :: proc {
	set_shader_uniform_i32,
	set_shader_uniform_f32,
	set_shader_uniform_b,
	set_shader_uniform_mat4,
	set_shader_uniform_vec3,
}

set_shader_uniform_i32 :: proc(program: Shader_Program, name: string, value: i32) {
	if name in program.uniforms {
		gl.Uniform1i(program.uniforms[name].location, value)
	} else {
		fmt.eprintf("Unable to set uniform \"%s\"\n", name)
	}
}

set_shader_uniform_b :: proc(program: Shader_Program, name: string, value: bool) {
	if name in program.uniforms {
		gl.Uniform1i(program.uniforms[name].location, i32(value))
	} else {
		fmt.eprintf("Unable to set uniform \"%s\"\n", name)
	}
}

set_shader_uniform_f32 :: proc(program: Shader_Program, name: string, value: f32) {
	if name in program.uniforms {
		gl.Uniform1f(program.uniforms[name].location, value)
	} else {
		fmt.eprintf("Unable to set uniform \"%s\"\n", name)
	}
}

set_shader_uniform_mat4 :: proc(program: Shader_Program, name: string, value: mat4) {
	copy := value
	if name in program.uniforms {
		gl.UniformMatrix4fv(program.uniforms[name].location, 1, gl.FALSE, raw_data(&copy))
	} else {
		fmt.eprintf("Unable to set uniform \"%s\"\n", name)
	}
}

set_shader_uniform_vec3 :: proc(program: Shader_Program, name: string, value: vec3) {
	if name in program.uniforms {
		gl.Uniform3f(program.uniforms[name].location, value.x, value.y, value.z)
	} else {
		fmt.eprintf("Unable to set uniform \"%s\"\n", name)
	}
}
