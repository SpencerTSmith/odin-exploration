package main

import "core:os"
import "core:fmt"
import "core:strings"

import gl "vendor:OpenGL"

// I think these will be helpful for catching bugs, enforcing typing on all handles
Shader :: distinct u32
Shader_Program :: distinct u32

Shader_Type :: enum {
	VERT = gl.VERTEX_SHADER,
	FRAG = gl.FRAGMENT_SHADER,
}

create_shader_from_string :: proc(source: string, type: Shader_Type) -> (shader: Shader, ok: bool) {
	shader = Shader(gl.CreateShader(u32(type)))
	source_ptr := strings.unsafe_string_to_cstring(source)
	length := i32(len(source))

	gl.ShaderSource(u32(shader), 1, &source_ptr, &length)
	gl.CompileShader(u32(shader))

	success: i32
	gl.GetShaderiv(u32(shader), gl.COMPILE_STATUS, &success)
	if success == 0 {
		info: [512]u8
		gl.GetShaderInfoLog(u32(shader), 512, nil, raw_data(info[:]))
		fmt.eprintf("Error compiling shader:\n%s", string(info[0:len(info)-1]))
		ok = false
		return
	}

	// TODO(ss): actually check for errors
	ok = true
	return
}

create_shader_from_file :: proc(file_path: string, type: Shader_Type) -> (shader: Shader, ok: bool) {
	source, file_ok := os.read_entire_file(file_path, context.temp_allocator)
	if !file_ok {
		fmt.eprintln("Could read shader file")
		ok = false
		return
	}
	defer free_all(context.temp_allocator) // Don't need to keep this around

	shader, ok = create_shader_from_string(string(source), type)
	return
}

delete_shader :: proc(shader: Shader) {
	gl.DeleteShader(u32(shader))
}

create_shader_program :: proc(vert_path, frag_path: string) -> (program: Shader_Program, ok: bool) {
	vert := create_shader_from_file(vert_path, Shader_Type.VERT) or_return
	frag := create_shader_from_file(frag_path, Shader_Type.FRAG) or_return

	program = Shader_Program(gl.CreateProgram())
	gl.AttachShader(u32(program), u32(vert))
	gl.AttachShader(u32(program), u32(frag))
	gl.LinkProgram(u32(program))

	success: i32
	gl.GetProgramiv(u32(program), gl.LINK_STATUS, &success)
	if success == 0 {
		info: [512]u8
		gl.GetProgramInfoLog(u32(program), 512, nil, raw_data(info[:]))
		fmt.eprintf("Error linking shader program:\n%s", string(info[0:len(info)-1]))
		ok = false
		return
	}

	ok = true
	return
}

use_shader_program :: proc(program: Shader_Program) {
	gl.UseProgram(u32(program))
}
