package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:math/rand"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "core:time"

import gl "vendor:OpenGL"
import "vendor:glfw"

WINDOW_DEFAULT_TITLE :: "Heraclitus"
WINDOW_DEFAULT_W :: 1280 * 1.5
WINDOW_DEFAULT_H :: 720 * 1.5

FRAMES_IN_FLIGHT :: 2
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

GL_MAJOR :: 4
GL_MINOR :: 6

State :: struct {
  running:           bool,
  paused:            bool,
  window:            Window,

  perm:              virtual.Arena,
  perm_alloc:        mem.Allocator,

  camera:            Camera,

  start_time:        time.Time,
  frame_count:       u64,

  clear_color:       vec3,

  z_near:            f32,
  z_far:             f32,

  sun:               Direction_Light,

  flashlight:        Spot_Light,
  flashlight_on:     bool,

  phong_program:     Shader_Program,

  current_shader:    Shader_Program,
  current_material:  Material,
}

init_state :: proc() -> (ok: bool) {
  using state
  start_time = time.now()

  if glfw.Init() != glfw.TRUE {
    fmt.println("Failed to initialize GLFW")
    return
  }

  glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
  glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
  glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)

  window.handle = glfw.CreateWindow(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H, WINDOW_DEFAULT_TITLE, nil, nil)
  if window.handle == nil {
    fmt.println("Failed to create GLFW window")
    return
  }

  window.w     = WINDOW_DEFAULT_W
  window.h     = WINDOW_DEFAULT_H
  window.title = WINDOW_DEFAULT_TITLE

  glfw.SetWindowUserPointer(window.handle, &window)

  c_title := strings.clone_to_cstring(window.title, allocator = context.temp_allocator)
  defer free_all(context.temp_allocator)

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

  gl.Enable(gl.CULL_FACE)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

  err := virtual.arena_init_growing(&perm)
  if err != .None {
    fmt.println("Can't create permanent arena")
    return
  }
  perm_alloc = virtual.arena_allocator(&perm)

  camera.sensitivity = 0.2
  camera.yaw         = 270.0
  camera.move_speed  = 10.0
  camera.position.z  = 5.0
  camera.fov_y       = glsl.radians_f32(90.0)

  running = true

  clear_color = BLACK

  z_near = 0.2
  z_far  = 100.0

  phong_program = make_shader_program("./shaders/simple.vert", "./shaders/phong.frag", allocator=perm_alloc) or_return

  sun = {
    direction = {0.0,  1.0, -1.0},

    color     = {1.0,  0.8,  0.7},
    intensity = 0.5,
    ambient   = 0.1,
  }

  flashlight = {
    inner_cutoff = math.cos(math.to_radians_f32(12.5)),
    outer_cutoff = math.cos(math.to_radians_f32(17.5)),

    direction = {0.0, 0.0, -1.0},
    position  = state.camera.position,

    color     = {0.3, 0.5,  1.0},
    intensity = 1.0,
    ambient   = 0.1,

    attenuation = {1.0, 0.007, 0.0002},
  }
  flashlight_on = false

  ok = true
  return
}

begin_drawing :: proc() {
  using state

  gl.ClearColor(clear_color.r, clear_color.g, clear_color.b, 1.0)
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

flush_drawing :: proc() {
  using state

  // TODO: More logic, batching, instancing, indirect, etc would be nice

  glfw.SwapBuffers(window.handle)
}

// NOTE: Global for now?
state: State

main :: proc() {
  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    defer {
      if len(track.allocation_map) > 0 {
        fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
          fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
        }
      }
      if len(track.bad_free_array) > 0 {
        fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
          fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
        }
      }
      mem.tracking_allocator_destroy(&track)
    }
  }

  if !init_state() do return
  defer free_state()

  gltf_test_model, _ := make_model_from_file("./assets/test_cube_gltf/BoxTextured.gltf")
  defer free_model(&gltf_test_model)

  floor_model, _ := make_model()
  defer free_model(&floor_model)
  floor: Entity = {
    position = {0.0, -5.0, 0.0},
    scale    = {100.0, 0.5, 100.0},
    model    = &floor_model
  }

  helmet_model, _ := make_model_from_file("./assets/helmet/DamagedHelmet.gltf")
  defer free_model(&helmet_model)
  helmet: Entity = {
    position = {-5.0, 0.0, 5.0},
    rotation = {90.0, 90.0, 0.0},
    scale    = {1.0, 1.0, 1.0},
    model    = &helmet_model,
  }

  duck_model, _ := make_model_from_file("./assets/duck/Duck.gltf")
  defer free_model(&duck_model)
  duck: Entity = {
    position = {5.0, 0.0, 0.0},
    scale = {0.01, 0.01, 0.01},
    model = &duck_model,
  }

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
    e.position = positions[idx % 10]
    e.rotation.x = 2 * f32(idx) * math.to_radians_f32(270.0)
    e.rotation.y = 2 * f32(idx) * math.to_radians_f32(180.0)
    e.rotation.z = 2 * f32(idx) * math.to_radians_f32(90.0)
    e.scale = {1.0, 1.0, 1.0}
    e.model = &gltf_test_model
  }

  POINT_LIGHT_COUNT :: 7
  point_lights: [POINT_LIGHT_COUNT]Point_Light
  for &pl, idx in point_lights {
    pl.position =    {f32(math.lerp(0.0, 5.0, rand.float64())), f32(math.lerp(0.0, 5.0, rand.float64())), f32(math.lerp(0.0, 20.0, rand.float64()))}

    pl.color =       {rand.float32(), rand.float32(), rand.float32()}
    pl.intensity =    0.8
    pl.ambient =      0.01

    pl.attenuation = {1.0, 0.022, 0.0019}
  }
  point_lights[0].position = { 50.0, 5.0,  50.0}
  point_lights[1].position = {-50.0, 5.0, -50.0}
  point_lights[2].position = { 50.0, 5.0, -50.0}
  point_lights[3].position = {-50.0, 5.0,  50.0}

  frame_uniform := make_uniform_buffer(size_of(Frame_UBO))
  bind_uniform_buffer_base(frame_uniform, .FRAME)
  defer free_uniform_buffer(&frame_uniform)

  light_uniform := make_uniform_buffer(size_of(Light_UBO))
  bind_uniform_buffer_base(light_uniform, .LIGHT)
  defer free_uniform_buffer(&light_uniform)

  grass_material,_ := make_material("./assets/grass.png")
  grass_model,_    := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, grass_material)
  defer free_model(&grass_model)
  grass := Entity{
    position = {0.0, -3.0, 0.0},
    scale    = {3.0, 3.0, 3.0},
    model    = &grass_model,
  }

  window_material,_ := make_material("./assets/blending_transparent_window.png")
  window_model,_    := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, window_material)
  window := Entity{
    position = {5.0,  0.0, 5.0},
    scale    = {1.0, 1.0, 1.0},
    model    = &window_model,
  }

  last_frame_time := time.tick_now()
  dt_s := 0.0
  for (!should_close()) {
    do_input(dt_s)

    // dt and sleeping
    {
      if (time.tick_since(last_frame_time) < TARGET_FRAME_TIME_NS) {
        time.accurate_sleep(TARGET_FRAME_TIME_NS - time.tick_since(last_frame_time))
      }

      // New dt after sleeping
      dt_s = f64(time.tick_since(last_frame_time)) / BILLION

      fps := 1.0 / dt_s

      // TODO(ss): Font rendering so we can just render it in game
      if u64(fps) != 0 && state.frame_count % u64(fps) == 0 {
        update_window_title_fps_dt(state.window, fps, dt_s)
      }

      state.frame_count += 1
      last_frame_time = time.tick_now()
    }

    // Update
    {
      state.flashlight.position = state.camera.position
      state.flashlight.direction = get_camera_forward(state.camera)

      for &e, idx in entities {
        e.rotation.x += 10 * f32(dt_s)
        e.rotation.y += 10 * f32(dt_s)
        e.rotation.z += 10 * f32(dt_s)
      }

      for &pl, idx in point_lights {
        seconds := seconds_since_start()
        pl.position.x = 4.0 * f32(dt_s) * f32(math.sin(.5 * math.PI * seconds)) + pl.position.x
        pl.position.y = 4.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds)) + pl.position.y
        pl.position.z = 4.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds)) + pl.position.z
      }
    }

    // Draw
    {
      begin_drawing()
      defer flush_drawing()

      view := get_camera_view(state.camera)
      projection := get_camera_perspective(state.camera, get_aspect_ratio(state.window), state.z_near, state.z_far)

      // Update frame uniform
      frame_ubo: Frame_UBO = {
        view            = view,
        projection      = projection,
        camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
        z_near          = state.z_near,
        z_far           = state.z_far,
        debug_mode      = .NONE,
      }
      write_uniform_buffer(frame_uniform, 0, size_of(frame_ubo), &frame_ubo)

      // Update light uniform
      light_ubo: Light_UBO
      light_ubo.direction = state.sun
      light_ubo.spot =      state.flashlight if state.flashlight_on else {}
      for &pl, idx in point_lights {
        light_ubo.points[idx] = pl
        light_ubo.points_count += 1
      }
      write_uniform_buffer(light_uniform, 0, size_of(light_ubo), &light_ubo)

      bind_shader_program(state.phong_program)
      {
        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(floor))
        draw_model(floor.model^)

        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(helmet))
        draw_model(helmet.model^)

        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(duck))
        draw_model(duck.model^)


        for e in entities {
          set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(e))

          draw_model(e.model^)
        }

        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(grass))
        draw_model(grass.model^)
        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(window))
        draw_model(window.model^)
      }

      // Bind other shaders
    }

    free_all(context.temp_allocator)
  }
}

free_state :: proc() {
  using state

  free_shader_program(&phong_program)

  glfw.DestroyWindow(window.handle)
  // glfw.Terminate() // Causing crashes?
  virtual.arena_destroy(&perm)
}

seconds_since_start :: proc() -> (seconds: f64) {
  seconds = time.duration_seconds(time.since(state.start_time))
  return
}

do_input :: proc(dt_s: f64) {
  using state
  glfw.PollEvents()

  // Mouse look
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

  if glfw.GetKey(window.handle, glfw.KEY_TAB) == glfw.PRESS {
    paused = !paused

    if paused do glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
    else do glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
  }

  // FIXME: Need to keep track of last input state
  if glfw.GetKey(window.handle, glfw.KEY_F) == glfw.PRESS {
    flashlight_on = !flashlight_on;
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
  camera.position += input_direction * camera.move_speed * f32(dt_s)
}

Window :: struct {
  handle:   glfw.WindowHandle,
  w, h:     u32,
  cursor_x: f64,
  cursor_y: f64,
  title:    string,
}

resize_window :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
  gl.Viewport(0, 0, width, height)
  window_struct := cast(^Window)glfw.GetWindowUserPointer(window)
  window_struct.w = u32(width)
  window_struct.h = u32(height)
}

get_aspect_ratio :: proc(window: Window) -> (aspect: f32) {
  aspect = f32(window.w) / f32(window.h)
  return
}

update_window_title_fps_dt :: proc(window: Window, fps, dt_s: f64) {
  buffer: [512]u8
  fmt.bprintf(buffer[:], "%s FPS: %f, DT: %f", window.title, fps, dt_s)
  c_str := cstring(raw_data(buffer[:]))
  glfw.SetWindowTitle(window.handle, c_str)
}

should_close :: proc() -> bool {
  return bool(glfw.WindowShouldClose(state.window.handle)) || !state.running
}

