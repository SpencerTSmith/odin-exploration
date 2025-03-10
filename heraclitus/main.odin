package main

import "core:fmt"
import "core:c"
import "core:mem"
import "core:math/linalg/glsl"
import "core:strings"

import "vendor:glfw"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Title"
WINDOW_DEFAULT_W :: 800
WINDOW_DEFAULT_H :: 600

FRAMES_IN_FLIGHT :: 1

GL_MAJOR :: 4
GL_MINOR :: 6

resize_window :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
	window_struct := cast(^Window)glfw.GetWindowUserPointer(window)
	window_struct.w = u32(width)
	window_struct.h = u32(height)
}

window_aspect_ratio :: proc(window: Window) -> (aspect: f32) {
	aspect = f32(window.w) / f32(window.h)
	return
}

window_should_close :: proc(window: Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

Window ::		struct {
	handle:		glfw.WindowHandle,
	w, h:			u32,
	cursor_x: f64,
	cursor_y: f64,
	title:		string,
}

State :: struct {
	running:		bool,
	window:			Window,
	perm:				mem.Arena,
	perm_alloc:	mem.Allocator,
	camera:			Camera,
}

init_state :: proc(state: ^State) {
	using state

	if glfw.Init() != glfw.TRUE {
		fmt.println("Failed to initialize GLFW")
		return
	}

	glfw.WindowHint(glfw.RESIZABLE,							glfw.FALSE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_PROFILE,				glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)

	window.handle = glfw.CreateWindow(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H, WINDOW_TITLE, nil, nil)
	if window.handle == nil {
		fmt.println("Failed to create GLFW window")
		return
	}

	window.w =			WINDOW_DEFAULT_W
	window.h = 			WINDOW_DEFAULT_H
	window.title =	"Heraclitus"

	glfw.SetWindowUserPointer(window.handle, &window)

	c_title := strings.unsafe_string_to_cstring(window.title)
	glfw.SetWindowTitle(window.handle, c_title)

	if glfw.RawMouseMotionSupported() {
		glfw.SetInputMode(window.handle, glfw.CURSOR,						glfw.CURSOR_DISABLED)
		glfw.SetInputMode(window.handle, glfw.RAW_MOUSE_MOTION, 1)
	}

	glfw.MakeContextCurrent(window.handle)
	glfw.SwapInterval(FRAMES_IN_FLIGHT)
	glfw.SetFramebufferSizeCallback(window.handle, resize_window)

	gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)
	gl.Enable(gl.DEPTH_TEST)

	perm_buffer: [64 * mem.Kilobyte]byte
	mem.arena_init(&perm, perm_buffer[:])
	perm_alloc = mem.arena_allocator(&perm)

	camera.sensitivity = 0.2
	camera.move_speed = 10.0
	camera.fov_y = glsl.radians_f32(90.0)

	running = true
	return
}

free_state :: proc(state: ^State) {
	using state
	glfw.DestroyWindow(window.handle)
	// glfw.Terminate() // Causing crashes?
	mem.arena_free_all(&perm)
}

do_input :: proc(state: ^State, dt_s: f64) {
	using state

	glfw.PollEvents()

	if glfw.GetKey(window.handle, glfw.KEY_ESCAPE) == glfw.PRESS {
		running = false
	}

	{
		new_cursor_x, new_cursor_y := glfw.GetCursorPos(window.handle)

		// Don't really need the precision?
		x_delta := f32(new_cursor_x - window.cursor_x)
		y_delta := f32(new_cursor_y - window.cursor_y)

		camera.yaw -=		camera.sensitivity * x_delta
		camera.pitch -= camera.sensitivity * y_delta
		camera.pitch = clamp(camera.pitch, -89.0, 89.0)

		window.cursor_x = new_cursor_x
		window.cursor_y = new_cursor_y
	}
}

main :: proc() {
	state: State
	init_state(&state)
	defer free_state(&state)

	// mesh := make_mesh_from_data(DEFAULT_TRIANGLE_VERT, nil)
	mesh := make_mesh_from_data(DEFAULT_RECT_VERT, DEFAULT_RECT_IDX)
	defer free_mesh(&mesh)

	texture, _ := make_texture("assets/container.jpg", Pixel_Format.RGB)
	defer free_texture(&texture)
	smile, _ := make_texture("assets/awesomeface.png", Pixel_Format.RGBA)
	defer free_texture(&smile)

	program, _ := make_shader_program("shaders/simple.vert", "shaders/simple.frag", state.perm_alloc)
	defer free_shader_program(program)

	entities: [1]Entity
	for &e, idx in entities {
		f_idx := f32(idx)
		e.position = {f_idx, f_idx, -1.0}
		e.scale = {1.0, 1.0, 1.0}
	}

	for (!window_should_close(state.window) && state.running) {
		do_input(&state, 0.0)

		// Update
		{
			for &e, idx in entities {
				// e.rotation.z += 30
			}
		}

		// Render
		{
			gl.ClearColor(0.2, 0.3, 0.3, 1.0)
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
			use_shader_program(program)

			bind_texture(texture, 0)
			bind_texture(smile, 1)
			set_shader_uniform_i32(program, "tex0", 0)
			set_shader_uniform_i32(program, "tex1", 1)

			for e in entities {
				model :=			get_entity_model_mat4(e)
				view :=				get_camera_view(state.camera)
				projection := get_camera_perspective(state.camera, window_aspect_ratio(state.window), 0.1, 100.0)

				set_shader_uniform(program, "model", &model)
				set_shader_uniform(program, "view", &view)
				set_shader_uniform(program, "projection", &projection)

				draw_mesh(mesh)
			}
		}

		glfw.SwapBuffers(state.window.handle)
	}
}

