package main

import "core:fmt"
import "core:c"

import "vendor:glfw"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Title"
WINDOW_DEFAULT_W :: 800
WINDOW_DEFAULT_H :: 600

FRAMES_IN_FLIGHT :: 1

GL_MAJOR :: 4
GL_MINOR :: 6

running := true

resize :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

tri_verts :[]f32 = {
    -0.5, -0.5, 0.0,
     0.5, -0.5, 0.0,
     0.0,  0.5, 0.0,
};

vert_source :string = `
#version 450 core
layout(location = 0) in vec3 in_position;

void main() {
    gl_Position = vec4(in_position.x, in_position.y, in_position.z, 1.0);
}
`
frag_source :string = `
#version 450 core

out vec4 out_color;

void main()
{
    out_color = vec4(1.0f, 0.5f, 0.2f, 1.0f);
}
`

main :: proc() {
	if glfw.Init() != glfw.TRUE {
		fmt.println("Failed to initialize GLFW")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)

	window := glfw.CreateWindow(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H, WINDOW_TITLE, nil, nil)
	defer glfw.DestroyWindow(window)

	if window == nil {
		fmt.println("Failed to GLFW window")
		return
	}

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(FRAMES_IN_FLIGHT)
	glfw.SetFramebufferSizeCallback(window, resize)

	gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address);

	vao: u32
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	vbo: u32
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(tri_verts) * size_of(tri_verts[0]), raw_data(tri_verts), gl.STATIC_DRAW)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), uintptr(0))
	gl.EnableVertexAttribArray(0)

	program, ok := gl.load_shaders_source(vert_source, frag_source)
	if !ok {
		fmt.eprintln("Failed to create shader program")
		return
	}

	for (!glfw.WindowShouldClose(window) && running) {
		glfw.PollEvents()
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			running = false
		}

		gl.ClearColor(0.2, 0.3, 0.3, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		gl.UseProgram(program)
		gl.BindVertexArray(vao)
		gl.DrawArrays(gl.TRIANGLES, 0, 3)

		glfw.SwapBuffers(window)
	}
}

