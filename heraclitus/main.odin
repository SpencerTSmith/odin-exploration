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


main :: proc() {
	if glfw.Init() != glfw.TRUE {
		fmt.println("Failed to initialize GLFW")
		return
	}
	// defer glfw.Terminate()

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

	gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)

	// mesh := make_mesh_from_data(DEFAULT_TRIANGLE_VERT, nil)
	mesh := make_mesh_from_data(DEFAULT_RECT_VERT, DEFAULT_RECT_IDX)
	defer free_mesh(&mesh)

	texture, _ := make_texture("assets/container.jpg", Pixel_Format.RGB)
	defer free_texture(&texture)
	smile, _ := make_texture("assets/awesomeface.png", Pixel_Format.RGBA)
	defer free_texture(&smile)

	program, _ := make_shader_program("shaders/simple.vert", "shaders/simple.frag")
	defer free_shader_program(program)

		use_shader_program(program)
		use_texture(texture, 0)
		use_texture(smile, 1)
		set_shader_uniform_i32(program, "tex0", 0)
		set_shader_uniform_i32(program, "tex1", 1)

	for (!glfw.WindowShouldClose(window) && running) {
		glfw.PollEvents()
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			running = false
		}

		gl.ClearColor(0.2, 0.3, 0.3, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		draw_mesh(mesh)

		glfw.SwapBuffers(window)
	}
}

