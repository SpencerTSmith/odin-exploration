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
  sun_on:            bool,

  flashlight:        Spot_Light,
  flashlight_on:     bool,

  phong_program:     Shader_Program,

  frame_buffer:      Frame_Buffer,
  post_program:      Shader_Program,

  // TODO: collapse to just one
  frame_uniform:     Uniform_Buffer,
  light_uniform:     Uniform_Buffer,

  current_shader:    Shader_Program,
  current_material:  Material,

  skybox:            Model,
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

  gl.Enable(gl.STENCIL_TEST)
  gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)

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
    direction = {1.0,  -1.0, 1.0},

    color     = {0.9,  0.8,  0.6},
    intensity = 1.0,
    ambient   = 0.2,
  }
  sun_on = true

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

  frame_buffer      = make_frame_buffer(state.window.w, state.window.h) or_return
  post_program = make_shader_program("./shaders/post.vert", "./shaders/post.frag", allocator=perm_alloc) or_return

  frame_uniform = make_uniform_buffer(size_of(Frame_UBO))
  bind_uniform_buffer_base(frame_uniform, .FRAME)

  light_uniform = make_uniform_buffer(size_of(Light_UBO))
  bind_uniform_buffer_base(light_uniform, .LIGHT)


  ok = true
  return
}

begin_drawing :: proc() {
  using state
  // We render into this first
  gl.BindFramebuffer(gl.FRAMEBUFFER, frame_buffer.id)
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
  gl.Enable(gl.DEPTH_TEST)
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

  cube_map_paths:[6]string = {
    "./assets/skybox/right.jpg",
    "./assets/skybox/left.jpg",
    "./assets/skybox/top.jpg",
    "./assets/skybox/bottom.jpg",
    "./assets/skybox/front.jpg",
    "./assets/skybox/back.jpg",
  }
  cube_map, ok := make_texture_from_cube_map(cube_map_paths)
  defer free_texture(&cube_map)

  container_model,_ := make_model_from_default_container()
  positions := DEFAULT_MODEL_POSITIONS
  entities: [10]Entity
  for &e, idx in entities {
    e.position = positions[idx % 10]
    e.rotation.x = 2 * f32(idx) * math.to_radians_f32(270.0)
    e.rotation.y = 2 * f32(idx) * math.to_radians_f32(180.0)
    e.rotation.z = 2 * f32(idx) * math.to_radians_f32(90.0)
    e.scale = {1.0, 1.0, 1.0}
    e.model = &container_model
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

  SCREEN_QUAD_VERTICES :: []f32{
    // position , uv
    -1.0,  1.0,  0.0, 1.0,
    -1.0, -1.0,  0.0, 0.0,
     1.0, -1.0,  1.0, 0.0,

    -1.0,  1.0,  0.0, 1.0,
     1.0, -1.0,  1.0, 0.0,
     1.0,  1.0,  1.0, 1.0
  }

  screen_verts := SCREEN_QUAD_VERTICES

  screen_buffer: u32
  gl.CreateBuffers(1, &screen_buffer)
  gl.NamedBufferStorage(screen_buffer, len(screen_verts) * size_of(f32), raw_data(screen_verts), 0)

  screen_vao: u32
  gl.CreateVertexArrays(1, &screen_vao)
  gl.VertexArrayVertexBuffer(screen_vao, 0, screen_buffer, 0, 4 * size_of(f32))

  // Position
  gl.EnableVertexArrayAttrib(screen_vao,  0)
  gl.VertexArrayAttribFormat(screen_vao,  0, 2, gl.FLOAT, gl.FALSE, 0)
  gl.VertexArrayAttribBinding(screen_vao, 0, 0)

  // UV
  gl.EnableVertexArrayAttrib(screen_vao,  1)
  gl.VertexArrayAttribFormat(screen_vao,  1, 2, gl.FLOAT, gl.FALSE, 2 * size_of(f32))
  gl.VertexArrayAttribBinding(screen_vao, 1, 0)

  SKYBOX_VERTICES :: []f32{
    -1.0,  1.0, -1.0,
    -1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
     1.0,  1.0, -1.0,
    -1.0,  1.0, -1.0,
    -1.0, -1.0,  1.0,
    -1.0, -1.0, -1.0,
    -1.0,  1.0, -1.0,
    -1.0,  1.0, -1.0,
    -1.0,  1.0,  1.0,
    -1.0, -1.0,  1.0,
     1.0, -1.0, -1.0,
     1.0, -1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0, -1.0,
     1.0, -1.0, -1.0,
    -1.0, -1.0,  1.0,
    -1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0, -1.0,  1.0,
    -1.0, -1.0,  1.0,
    -1.0,  1.0, -1.0,
     1.0,  1.0, -1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
    -1.0,  1.0,  1.0,
    -1.0,  1.0, -1.0,
    -1.0, -1.0, -1.0,
    -1.0, -1.0,  1.0,
     1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
    -1.0, -1.0,  1.0,
     1.0, -1.0,  1.0
  }
  skybox_verts := SKYBOX_VERTICES

  skybox_buffer: u32
  gl.CreateBuffers(1, &skybox_buffer)
  gl.NamedBufferStorage(skybox_buffer, len(skybox_verts) * size_of(f32), raw_data(skybox_verts), 0)

  skybox_vao: u32
  gl.CreateVertexArrays(1, &skybox_vao)
  gl.VertexArrayVertexBuffer(skybox_vao, 0, skybox_buffer, 0, 3 * size_of(f32))

  // Position
  gl.EnableVertexArrayAttrib(skybox_vao,  0)
  gl.VertexArrayAttribFormat(skybox_vao,  0, 3, gl.FLOAT, gl.FALSE, 0)
  gl.VertexArrayAttribBinding(skybox_vao, 0, 0)

  skybox_program, okk := make_shader_program("./shaders/skybox.vert", "./shaders/skybox.frag")
  if !okk {
    return
  }
  defer free_shader_program(&skybox_program)

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
    begin_drawing()
    {
      defer flush_drawing()

      // Update frame uniform
      frame_ubo: Frame_UBO = {
        projection      = get_camera_perspective(state.camera, get_aspect_ratio(state.window), state.z_near, state.z_far),
        view            = get_camera_view(state.camera),
        camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
        z_near          = state.z_near,
        z_far           = state.z_far,
        debug_mode      = .NONE,
      }
      write_uniform_buffer(state.frame_uniform, 0, size_of(frame_ubo), &frame_ubo)

      // Update light uniform
      light_ubo: Light_UBO
      light_ubo.direction = state.sun
      light_ubo.spot =      state.flashlight if state.flashlight_on else {}
      for &pl, idx in point_lights {
        light_ubo.points[idx] = pl
        light_ubo.points_count += 1
      }
      write_uniform_buffer(state.light_uniform, 0, size_of(light_ubo), &light_ubo)

      bind_shader_program(skybox_program)
      {
        gl.DepthMask(gl.FALSE)
        gl.BindVertexArray(skybox_vao)
        bind_texture(cube_map, 0)
        set_shader_uniform(skybox_program, "skybox", 0)
        gl.DrawArrays(gl.TRIANGLES, 0, 36)
        gl.DepthMask(gl.TRUE)
      }

      // Main pass, we are drawing into the main frame_buffer
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


        // TODO: A way to flag models as having transparency, and to queue these up for rendering,
        // after all opaque have been called to draw. Then also a way to sort these transparent models
        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(grass))
        draw_model(grass.model^)
        set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(window))
        draw_model(window.model^)
      }

      // Post-Processing Pass
      gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
      gl.Clear(gl.COLOR_BUFFER_BIT)
      gl.Disable(gl.DEPTH_TEST)

      bind_shader_program(state.post_program)
      {
        bind_texture(state.frame_buffer.color_target, 0)
        set_shader_uniform(state.post_program, "screen_texture", 0)

        gl.BindVertexArray(screen_vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)
      }
    }

    free_all(context.temp_allocator)
  }
}

free_state :: proc() {
  using state

  free_uniform_buffer(&light_uniform)
  free_uniform_buffer(&frame_uniform)

  free_shader_program(&phong_program)
  free_shader_program(&post_program)

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
