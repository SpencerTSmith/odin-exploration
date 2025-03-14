package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:mem"
import "core:strings"
import "core:time"

import gl "vendor:OpenGL"
import "vendor:glfw"

WINDOW_TITLE :: "Title"
WINDOW_DEFAULT_W :: 1280
WINDOW_DEFAULT_H :: 720

FRAMES_IN_FLIGHT :: 2
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

GL_MAJOR :: 4
GL_MINOR :: 6

BILLION :: 1_000_000_000

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

update_window_title_fps_dt :: proc(window: Window, fps, dt_s: f64) {
	buffer: [512]u8
	fmt.bprintf(buffer[:], "%s FPS: %f, DT: %f", window.title, fps, dt_s)
	c_str := cstring(raw_data(buffer[:]))
	glfw.SetWindowTitle(window.handle, c_str)
}

window_should_close :: proc(window: Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

Window :: struct {
	handle:   glfw.WindowHandle,
	w, h:     u32,
	cursor_x: f64,
	cursor_y: f64,
	title:    string,
}

State :: struct {
	running:         bool,
	window:          Window,

	perm:            mem.Arena,
	perm_alloc:      mem.Allocator,
	tracking_alloc:  mem.Tracking_Allocator,

	camera:          Camera,

	dt_s:            f64,
	last_frame_time: time.Tick,
	start_time:			 time.Time,
	frame_count:		 u64,
}

init_state :: proc(state: ^State) {
	using state
	start_time = time.now()

	mem.tracking_allocator_init(&tracking_alloc, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_alloc)

	if glfw.Init() != glfw.TRUE {
		fmt.println("Failed to initialize GLFW")
		return
	}

	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)

	window.handle = glfw.CreateWindow(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H, WINDOW_TITLE, nil, nil)
	if window.handle == nil {
		fmt.println("Failed to create GLFW window")
		return
	}

	window.w = WINDOW_DEFAULT_W
	window.h = WINDOW_DEFAULT_H
	window.title = "Heraclitus"

	glfw.SetWindowUserPointer(window.handle, &window)

	c_title := strings.unsafe_string_to_cstring(window.title)
	glfw.SetWindowTitle(window.handle, c_title)

	if glfw.RawMouseMotionSupported() {
		glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
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
	camera.yaw = -90.0
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

seconds_since_start :: proc(state: State) -> (seconds: f64) {
	seconds = time.duration_seconds(time.since(state.start_time))
	return
}

do_input :: proc(state: ^State, dt_s: f64) {
	using state

	glfw.PollEvents()

	{
		new_cursor_x, new_cursor_y := glfw.GetCursorPos(window.handle)

		// Don't really need the precision?
		x_delta := f32(new_cursor_x - window.cursor_x)
		y_delta := f32(new_cursor_y - window.cursor_y)

		camera.yaw -= camera.sensitivity * x_delta
		camera.pitch -= camera.sensitivity * y_delta
		camera.pitch = clamp(camera.pitch, -89.0, 89.0)

		window.cursor_x = new_cursor_x
		window.cursor_y = new_cursor_y
	}

	if glfw.GetKey(window.handle, glfw.KEY_ESCAPE) == glfw.PRESS {
		running = false
	}

	input_direction: vec3
	camera_forward, camera_up, camera_right := get_camera_axes(camera)
	// Z, forward
	if glfw.GetKey(window.handle, glfw.KEY_W) == glfw.PRESS {
		input_direction += camera_forward
	}
	if glfw.GetKey(window.handle, glfw.KEY_S) == glfw.PRESS {
		input_direction -= camera_forward
	}

	// Y, vertical
	if glfw.GetKey(window.handle, glfw.KEY_SPACE) == glfw.PRESS {
		input_direction += camera_up
	}
	if glfw.GetKey(window.handle, glfw.KEY_LEFT_CONTROL) == glfw.PRESS {
		input_direction -= camera_up
	}

	// X, strafe
	if glfw.GetKey(window.handle, glfw.KEY_D) == glfw.PRESS {
		input_direction += camera_right
	}
	if glfw.GetKey(window.handle, glfw.KEY_A) == glfw.PRESS {
		input_direction -= camera_right
	}

	input_direction = linalg.normalize0(input_direction)

	camera.position += input_direction * camera.move_speed * f32(dt_s) // Maybe not so good
}


main :: proc() {
	state: State
	init_state(&state)
	defer free_state(&state)

	mesh := make_mesh_from_data(DEFAULT_CUBE_VERT, nil)
	defer free_mesh(&mesh)

	material, _ := make_material("assets/container2.png", "assets/container2_specular.png", "", 64.0)
	defer free_material(&material)

	smile, _ := make_texture("assets/awesomeface.png")
	defer free_texture(&smile)

	phong_program, ok := make_shader_program("shaders/simple.vert", "shaders/phong.frag", state.perm_alloc)
	if !ok {
		return
	}
	defer free_shader_program(phong_program)

	light_source_program, ok1 := make_shader_program("shaders/simple.vert", "shaders/light_source.frag", state.perm_alloc)
	if !ok1 {
		return
	}
	defer free_shader_program(light_source_program)

	positions: [10]vec3 = {
    { 0.0,  0.0,   0.0},
    { 2.0,  5.0, -15.0},
    {-1.5, -2.2,  -2.5},
    {-3.8, -2.0, -12.3},
    { 2.4, -0.4,  -3.5},
    {-1.7,  3.0,  -7.5},
    { 1.3, -2.0,  -2.5},
    { 1.5,  2.0,  -2.5},
    { 1.5,  0.2,  -1.5},
    {-1.3,  1.0,  -1.5},
	}

	entities: [10]Entity
	for &e, idx in entities {
		e.position = positions[idx]
		// e.position.z -= 5.0
		e.rotation.x = 2 * f32(idx) * math.to_radians_f32(270.0)
		e.rotation.y = 2 * f32(idx) * math.to_radians_f32(180.0)
		e.rotation.z = 2 * f32(idx) * math.to_radians_f32(90.0)
		e.scale = {1.0, 1.0, 1.0}
		e.mesh = &mesh
	}

	light_entity: Entity = {
		position = {0.0, 2.0, -2.0},
		scale    = {0.5, 0.5, 0.5},
		mesh     = &mesh,
	}

	point_lights: [10]Point_Light
	for &pl, idx in point_lights {
		pl.position = light_entity.position

		pl.color =		{1.0, 1.0, 1.0}
		pl.ambient =	{0.2, 0.2, 0.2}
		pl.diffuse =	{0.5, 0.5, 0.5}
		pl.specular = {1.0, 1.0, 1.0}

		pl.constant =	 1.0
		pl.linear =		 0.022
		pl.quadratic = 0.0019
	}

	direction_light: Direction_Light = {
		direction = {0.0, -1.0, -1.0},

		color =			{1.0,  1.0,  1.0},
		ambient =		{0.2,  0.2,  0.2},
		diffuse =		{0.5,  0.5,  0.5},
		specular =	{1.0,  1.0,  1.0},
	}

	spot_light: Spot_Light = {
		direction = {0.0, 0.0, -1.0},

		color =			{1.0, 1.0,  1.0},
		ambient =		{0.2, 0.2,  0.2},
		diffuse =		{0.5, 0.5,  0.5},
		specular =	{1.0, 1.0,  1.0},

		constant =	 1.0,
		linear =		 0.007,
		quadratic =  0.0002,

		cutoff = math.cos(math.to_radians_f32(12.5))
	}


	state.last_frame_time = time.tick_now()
	for (!window_should_close(state.window) && state.running) {
		do_input(&state, 0.0)

		// dt and sleeping
		{
			if (time.tick_since(state.last_frame_time) < TARGET_FRAME_TIME_NS) {
				time.accurate_sleep(TARGET_FRAME_TIME_NS - time.tick_since(state.last_frame_time))
			}

			// New dt after sleeping
			state.dt_s = f64(time.tick_since(state.last_frame_time)) / BILLION

			fps := 1.0 / state.dt_s

			// TODO(ss): Font rendering so we can just render it in game
			if state.frame_count % u64(fps) == 0 {
				update_window_title_fps_dt(state.window, fps, state.dt_s)
			}

			state.frame_count += 1
			state.last_frame_time = time.tick_now()
		}

		// Update
		{
			for &e, idx in entities {
				e.rotation.x += 10 * f32(state.dt_s)
				e.rotation.y += 10 * f32(state.dt_s)
				e.rotation.z += 10 * f32(state.dt_s)
			}

			light_entity.rotation.y += 360 * f32(state.dt_s)

			seconds := seconds_since_start(state)
			light_entity.position.x = 0.025 * f32(math.sin(.5 * math.PI * seconds)) + light_entity.position.x
			light_entity.position.y = 0.025 * f32(math.cos(.5 * math.PI * seconds)) + light_entity.position.y
			light_entity.position.z = 0.025 * f32(math.cos(.5 * math.PI * seconds)) + light_entity.position.z
		}

		// Render
		begin_frame()
		{
			view := get_camera_view(state.camera)
			projection := get_camera_perspective(state.camera, window_aspect_ratio(state.window), 0.1, 100.0)

			// Light Cube
			use_shader_program(light_source_program)
			{
				model := get_entity_model_mat4(light_entity)
				set_shader_uniform(light_source_program, "model", model)
				set_shader_uniform(light_source_program, "view", view)
				set_shader_uniform(light_source_program, "projection", projection)

				point_lights[0].position = light_entity.position

				draw_mesh(light_entity.mesh^)
			}

			use_shader_program(phong_program)
			for e in entities {
				model := get_entity_model_mat4(e)
				set_shader_uniform(phong_program, "model", model)
				set_shader_uniform(phong_program, "view", view)
				set_shader_uniform(phong_program, "projection", projection)

				set_shader_uniform(phong_program, "point_light.position",  light_entity.position)
				set_shader_uniform(phong_program, "point_light.color",		 point_lights[0].color)
				set_shader_uniform(phong_program, "point_light.ambient",   point_lights[0].ambient)
				set_shader_uniform(phong_program, "point_light.diffuse",   point_lights[0].diffuse)
				set_shader_uniform(phong_program, "point_light.specular",  point_lights[0].diffuse)
				set_shader_uniform(phong_program, "point_light.constant",  point_lights[0].constant)
				set_shader_uniform(phong_program, "point_light.linear",		 point_lights[0].linear)
				set_shader_uniform(phong_program, "point_light.quadratic", point_lights[0].quadratic)

				set_shader_uniform(phong_program, "direction_light.direction", direction_light.direction)
				set_shader_uniform(phong_program, "direction_light.color",		 direction_light.color)
				set_shader_uniform(phong_program, "direction_light.ambient",   direction_light.ambient)
				set_shader_uniform(phong_program, "direction_light.diffuse",   direction_light.diffuse)
				set_shader_uniform(phong_program, "direction_light.specular",  direction_light.specular)

				set_shader_uniform(phong_program, "spot_light.position",  state.camera.position)
				set_shader_uniform(phong_program, "spot_light.direction", get_camera_forward(state.camera))
				set_shader_uniform(phong_program, "spot_light.color",		  spot_light.color)
				set_shader_uniform(phong_program, "spot_light.ambient",   spot_light.ambient)
				set_shader_uniform(phong_program, "spot_light.diffuse",   spot_light.diffuse)
				set_shader_uniform(phong_program, "spot_light.specular",  spot_light.specular)
				set_shader_uniform(phong_program, "spot_light.constant",  spot_light.constant)
				set_shader_uniform(phong_program, "spot_light.linear",		spot_light.linear)
				set_shader_uniform(phong_program, "spot_light.quadratic", spot_light.quadratic)
				set_shader_uniform(phong_program, "spot_light.cutoff",		spot_light.cutoff)

				bind_material(material, phong_program)

				draw_mesh(e.mesh^)
			}
		}
		end_frame(state.window)

		free_all(context.temp_allocator)
	}

	if len(state.tracking_alloc.allocation_map) > 0 {
		fmt.println("Leaks:")
		for _, v in state.tracking_alloc.allocation_map {
			fmt.printf("\t%v\n\n", v)
		}
	}
}
