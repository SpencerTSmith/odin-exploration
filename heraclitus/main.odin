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
WINDOW_DEFAULT_W :: 1280 * 1.75
WINDOW_DEFAULT_H :: 720  * 1.75

FRAMES_IN_FLIGHT :: 1
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

GL_MAJOR :: 4
GL_MINOR :: 6

// TODO: actually use this instead of hardcoded paths
ASSET_DIR :: "assets"

Program_Mode :: enum {
  PLAY,
  MENU,
}

State :: struct {
  running:           bool,
  mode:              Program_Mode,

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
  skybox_program:    Shader_Program,
  post_program:      Shader_Program,

  ms_frame_buffer:   Framebuffer,

  skybox:            Skybox,

  // TODO: collapse to just one
  frame_uniform:     Uniform_Buffer,
  light_uniform:     Uniform_Buffer,

  current_shader:    Shader_Program,
  current_material:  Material,

  bound_textures:    [16]Texture,

  // NOTE: Needed to make any type of draw call?
  empty_vao:         u32,

  immediate:         Immediate_State,

  input:             Input_State,
}

init_state :: proc() -> (ok: bool) {
  using state
  start_time = time.now()

  if glfw.Init() != glfw.TRUE {
    fmt.println("Failed to initialize GLFW")
    return
  }

  mode = .PLAY

  glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
  glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
  glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)
  // glfw.WindowHint(glfw.SAMPLES, 4) We render into our own buffer

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

  gl.Enable(gl.MULTISAMPLE)

  gl.Enable(gl.DEPTH_TEST)

  gl.Enable(gl.CULL_FACE)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

  gl.Enable(gl.STENCIL_TEST)
  gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)

  err := virtual.arena_init_growing(&perm)
  if err != .None {
    fmt.println("Failed to create permanent arena")
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

  phong_program  = make_shader_program("simple.vert", "phong.frag",  allocator=perm_alloc) or_return
  skybox_program = make_shader_program("skybox.vert", "skybox.frag", allocator=perm_alloc) or_return
  post_program   = make_shader_program("post.vert",   "post.frag", allocator=perm_alloc) or_return

  sun = {
    direction = {1.0,  -1.0, 1.0, 0.0},

    color     = {0.9,  0.8,  0.6, 0.0},
    intensity = 0.8,
    ambient   = 0.1,
  }
  sun_on = true

  flashlight = {
    inner_cutoff = math.cos(math.to_radians_f32(12.5)),
    outer_cutoff = math.cos(math.to_radians_f32(17.5)),

    direction = {0.0, 0.0, -1.0, 0.0},
    position  = vec4_from_3(state.camera.position),

    color     = {0.3, 0.5,  1.0, 0.0},
    intensity = 1.0,
    ambient   = 0.1,

    attenuation = {1.0, 0.007, 0.0002, 0.0},
  }
  flashlight_on = false

  // TODO: Required right now to be more than 1 samples
  ms_frame_buffer = make_framebuffer(state.window.w, state.window.h, 2) or_return

  frame_uniform = make_uniform_buffer(size_of(Frame_UBO))
  bind_uniform_buffer_base(frame_uniform, .FRAME)

  light_uniform = make_uniform_buffer(size_of(Light_UBO))
  bind_uniform_buffer_base(light_uniform, .LIGHT)

  cube_map_paths:[6]string = {
    "./assets/skybox/right.jpg",
    "./assets/skybox/left.jpg",
    "./assets/skybox/top.jpg",
    "./assets/skybox/bottom.jpg",
    "./assets/skybox/front.jpg",
    "./assets/skybox/back.jpg",
  }
  skybox = make_skybox(cube_map_paths) or_return

  gl.CreateVertexArrays(1, &empty_vao)

  init_immediate_renderer() or_return

  ok = true

  return
}

begin_drawing :: proc() {

  // Hmm nothing now
}

begin_main_pass :: proc() {
  gl.BindFramebuffer(gl.FRAMEBUFFER, state.ms_frame_buffer.id)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
  gl.Enable(gl.DEPTH_TEST)
  gl.Enable(gl.CULL_FACE)
  gl.CullFace(gl.BACK)
}

begin_post_pass :: proc() {
  gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Clear(gl.COLOR_BUFFER_BIT)
  gl.Disable(gl.DEPTH_TEST)
}

// For now excludes transparent objects and the skybox
begin_shadow_pass :: proc(framebuffer: Framebuffer, x, y, width, height: int) {
  assert(framebuffer.depth_target.id > 0)
  gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.id)

  gl.Viewport(i32(x), i32(y), i32(width), i32(height))
  gl.Clear(gl.DEPTH_BUFFER_BIT)
  gl.Enable(gl.DEPTH_TEST)
  gl.Enable(gl.CULL_FACE)
  gl.CullFace(gl.FRONT) // Peter-panning fix for shadow bias
}

flush_drawing :: proc() {
  // TODO: More logic, batching, instancing, indirect, etc would be nice
  // to explore

  glfw.SwapBuffers(state.window.handle)
}

// NOTE: Global
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

  font, font_got := make_font("Diablo_Light.ttf", 60.0)

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

  POINT_LIGHT_COUNT :: 5
  point_lights: [POINT_LIGHT_COUNT]Point_Light
  for i in 0..<POINT_LIGHT_COUNT-1 {
    point_lights[i].color.rgb    = {rand.float32(), rand.float32(), rand.float32()}
    point_lights[i].attenuation  = {1.0, 0.022, 0.0019, 0.0}
    point_lights[i].intensity    = 0.8
    point_lights[i].ambient      = 0.01
  }
  point_lights[0].position.xyz = { 50.0, 5.0,  50.0}
  point_lights[1].position.xyz = {-50.0, 5.0, -50.0}
  point_lights[2].position.xyz = { 50.0, 5.0, -50.0}
  point_lights[3].position.xyz = {-50.0, 5.0,  50.0}

  point_lights[4].position.xyz = { 0.0, 0.0, 0.0}
  point_lights[4].color.rgb    = {rand.float32(), rand.float32(), rand.float32()}
  point_lights[4].intensity    = 0.8
  point_lights[4].ambient      = 0.01
  point_lights[4].attenuation  = {1.0, 0.022, 0.0019, 0.0}

  point_depth, ok2 := make_framebuffer(1024, 1024, 1, {.DEPTH_CUBE})
  if !ok2 do return

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
  defer free_model(&window_model)
  window := Entity{
    position = {5.0,  0.0, 5.0},
    scale    = {1.0, 1.0, 1.0},
    model    = &window_model,
  }

  SHADOW_MAP_WIDTH  :: 1024 * 2
  SHADOW_MAP_HEIGHT :: 1024 * 2

  sun_depth_buffer,_ := make_framebuffer(SHADOW_MAP_WIDTH, SHADOW_MAP_HEIGHT, 1, {.DEPTH})

  sun_shadow_program, ok := make_shader_program("direction_shadow.vert", "none.frag")
  defer free_shader_program(&sun_shadow_program)
  if !ok do return

  last_frame_time := time.tick_now()
  dt_s := 0.0
  for (!should_close()) {
    // Resize check
    if state.window.resized {
      // Reset
      state.window.resized = false

      ok: bool
      state.ms_frame_buffer, ok = remake_framebuffer(&state.ms_frame_buffer, state.window.w, state.window.h)
      fmt.println("Resizing multisampling framebuffer")
      // TODO: more graceful
      if !ok {
        fmt.println("Window has been resized but unable to recreate multisampling framebuffer")
        return
      }
    }

    // dt and sleeping
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

    update_input_state()

    if key_was_pressed(.ESCAPE) {
      toggle_menu()
    }

    switch state.mode {
      case .PLAY:
      // Update
      {
        update_player_input(dt_s)

        state.flashlight.position = vec4_from_3(state.camera.position)
        state.flashlight.direction = vec4_from_3(get_camera_forward(state.camera))

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
        // Update frame uniform
        frame_ubo: Frame_UBO = {
          projection      = get_camera_perspective(state.camera, get_aspect_ratio(state.window), state.z_near, state.z_far),
          orthographic    = get_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far),
          view            = get_camera_view(state.camera),
          camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
          z_near          = state.z_near,
          z_far           = state.z_far,
          debug_mode      = .NONE,
        }
        write_uniform_buffer(state.frame_uniform, 0, size_of(frame_ubo), &frame_ubo)

        // Update light uniform
        light_ubo: Light_UBO
        light_ubo.direction = state.sun if state.sun_on else {}
        light_ubo.spot =      state.flashlight if state.flashlight_on else {}
        for &pl, idx in point_lights {
          light_ubo.points[idx] = pl
          light_ubo.points_count += 1
        }
        write_uniform_buffer(state.light_uniform, 0, size_of(light_ubo), &light_ubo)

        // TODO: need to calc this for all shadow casting lights
        // So would be nice to do it up front and upload in light UBO
        // Or even just calculate on GPU?
        light_view := glsl.mat4LookAt({-2.0, 4.0, -1.0}, state.sun.direction.xyz, {0.0, 1.0, 0.0})
        light_proj := glsl.mat4Ortho3d(-20.0, 20.0, -20.0, 20.0, 0.1, 20.0)
        light_proj_view := light_proj * light_view

        begin_shadow_pass(sun_depth_buffer, 0, 0, SHADOW_MAP_WIDTH, SHADOW_MAP_HEIGHT)
        {
          bind_shader_program(sun_shadow_program)
          // Sun has no position, only direction
          set_shader_uniform(sun_shadow_program, "light_proj_view", light_proj_view)

          // Render scene as normal
          set_shader_uniform(sun_shadow_program, "model", get_entity_model_mat4(floor))
          draw_model(floor.model^)

          set_shader_uniform(sun_shadow_program, "model", get_entity_model_mat4(helmet))
          draw_model(helmet.model^)

          set_shader_uniform(sun_shadow_program, "model", get_entity_model_mat4(duck))
          draw_model(duck.model^)

          for e in entities {
            set_shader_uniform(sun_shadow_program, "model", get_entity_model_mat4(e))
            draw_model(e.model^)
          }
        }

        begin_main_pass()
        {
          // Opaque models
          bind_shader_program(state.phong_program)

          // FIXME: Maybe just keep track of currently bound texture locations and cycle through

          bind_texture(state.skybox.texture, 4)
          set_shader_uniform(state.phong_program, "skybox", 4)

          bind_texture(sun_depth_buffer.depth_target, 5)
          set_shader_uniform(state.phong_program, "light_depth", 5)
          set_shader_uniform(state.phong_program, "light_proj_view", light_proj_view)

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

          // Skybox here so it is seen behind transparent objects, binds its own shader
          {
            draw_skybox(state.skybox)
          }

          // Transparent models
          bind_shader_program(state.phong_program)
          {
            gl.Disable(gl.CULL_FACE)
            // TODO: A way to flag models as having transparency, and to queue these up for rendering,
            // after all opaque have been called to draw. Then also a way to sort these transparent models
            set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(grass))
            draw_model(grass.model^)

            set_shader_uniform(state.phong_program, "model", get_entity_model_mat4(window))
            draw_model(window.model^)
          }
        }

        // Post-Processing Pass, switch to the screens framebuffer
        begin_post_pass()
        {
          bind_shader_program(state.post_program)
          bind_texture(state.ms_frame_buffer.color_target, 0)
          set_shader_uniform(state.post_program, "screen_texture", 0)

          // Hardcoded vertices in post vertex shader, but opengl requires a VAO for draw calls
          gl.BindVertexArray(state.empty_vao)
          gl.DrawArrays(gl.TRIANGLES, 0, 6)
        }

        fps_text := fmt.aprintf("FPS: %f", fps, allocator = context.temp_allocator)
        draw_text(fps_text, font, 100, 100)
        draw_text("Hello, Sailor!", font, f32(state.window.w / 2), 100)

        immediate_quad(vec2{100, 100}, 300, 300, LEARN_OPENGL_ORANGE)
        immediate_quad(vec2{300, 300}, 300, 300, LEARN_OPENGL_BLUE)

      }
      case .MENU:
      draw_menu()
    }

    flush_drawing()
    // At the end of frame free this
    free_all(context.temp_allocator)
  }
}

free_state :: proc() {
  using state

  free_immediate_renderer()

  free_skybox(&skybox)

  free_uniform_buffer(&light_uniform)
  free_uniform_buffer(&frame_uniform)

  free_shader_program(&post_program)
  free_shader_program(&skybox_program)
  free_shader_program(&phong_program)

  glfw.DestroyWindow(window.handle)
  // glfw.Terminate() // Causing crashes?
  virtual.arena_destroy(&perm)
}

seconds_since_start :: proc() -> (seconds: f64) {
  seconds = time.duration_seconds(time.since(state.start_time))
  return
}

update_player_input :: proc(dt_s: f64) {
  using state

  // Don't really need the precision?
  x_delta := f32(input.mouse.curr_x - input.mouse.prev_x)
  y_delta := f32(input.mouse.curr_y - input.mouse.prev_y)

  camera.yaw   -= camera.sensitivity * x_delta
  camera.pitch -= camera.sensitivity * y_delta
  camera.pitch = clamp(camera.pitch, -89.0, 89.0)

  if key_was_pressed(.F) {
    flashlight_on = !flashlight_on;
  }

  input_direction: vec3
  camera_forward, camera_up, camera_right := get_camera_axes(camera)
  // Z, forward
  if key_is_down(.W) {
    input_direction += camera_forward
  }
  if key_is_down(.S) {
    input_direction -= camera_forward
  }

  // Y, vertical
  if key_is_down(.SPACE) {
    input_direction += camera_up
  }
  if key_is_down(.LEFT_CONTROL) {
    input_direction -= camera_up
  }

  // X, strafe
  if key_is_down(.D) {
    input_direction += camera_right
  }
  if key_is_down(.A) {
    input_direction -= camera_right
  }

  input_direction = linalg.normalize0(input_direction)
  camera.position += input_direction * camera.move_speed * f32(dt_s)
}
