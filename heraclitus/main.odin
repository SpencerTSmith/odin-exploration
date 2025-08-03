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
import "core:slice"

import gl "vendor:OpenGL"
import "vendor:glfw"

WINDOW_DEFAULT_TITLE :: "Heraclitus"
WINDOW_DEFAULT_W :: 1280 * 1.75
WINDOW_DEFAULT_H :: 720  * 1.75

FRAMES_IN_FLIGHT :: 3
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

GL_MAJOR :: 4
GL_MINOR :: 6

Program_Mode :: enum {
  GAME,
  MENU,
  EDIT,
}

Frame_Info :: struct {
  fence: gl.sync_t
}

State :: struct {
  running:          bool,
  mode:             Program_Mode,

  window:           Window,

  perm:             virtual.Arena,
  perm_alloc:       mem.Allocator,

  camera:           Camera,

  entities:         [dynamic]Entity,

  start_time:       time.Time,

  fps:              f64,
  frame_count:      uint,
  frames:           [FRAMES_IN_FLIGHT]Frame_Info,
  curr_frame_index: int,

  clear_color:      vec3,

  z_near:           f32,
  z_far:            f32,

  sun:              Direction_Light,
  sun_on:           bool,

  flashlight:       Spot_Light,
  flashlight_on:    bool,

  // Could maybe replace this but this makes it easier to add them
  shaders:          map[string]Shader_Program,

  ms_frame_buffer:  Framebuffer,

  skybox:           Skybox,

  frame_uniforms:   GPU_Buffer,

  // TODO: Maybe these should be pointers and not copies
  current_shader:   Shader_Program,
  current_material: Material,
  bound_textures:   [16]Texture,

  // NOTE: Needed to make draw calls, even if not using one
  empty_vao:        u32,

  input:            Input_State,

  draw_debug_stats: bool,
  default_font:     Font,
}

init_state :: proc() -> (ok: bool) {
  using state
  start_time = time.now()

  if glfw.Init() != glfw.TRUE {
    fmt.println("Failed to initialize GLFW")
    return
  }

  mode = .GAME

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

  // HACK: Just giving it access to the global struct... probably bad practice
  glfw.SetWindowUserPointer(window.handle, &state)

  c_title := strings.clone_to_cstring(window.title, allocator = context.temp_allocator)
  defer free_all(context.temp_allocator)

  glfw.SetWindowTitle(window.handle, c_title)

  if glfw.RawMouseMotionSupported() {
    glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    glfw.SetInputMode(window.handle, glfw.RAW_MOUSE_MOTION, 1)
  }

  glfw.MakeContextCurrent(window.handle)
  glfw.SwapInterval(1)

  glfw.SetFramebufferSizeCallback(window.handle, resize_window_callback)
  glfw.SetScrollCallback(window.handle, mouse_scroll_callback)

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

  camera = {
    sensitivity  = 0.2,
    yaw          = 270.0,
    move_speed   = 10.0,
    position     = {0.0, 0.0, 5.0},
    curr_fov_y   = 90.0,
    target_fov_y = 90.0,
  }

  entities = make([dynamic]Entity, perm_alloc)

  running = true

  clear_color = BLACK.rgb

  z_near = 0.2
  z_far  = 100.0

  shaders = make(map[string]Shader_Program, allocator=perm_alloc)

  shaders["phong"]     = make_shader_program("simple.vert", "phong.frag",  allocator=perm_alloc) or_return
  shaders["skybox"]    = make_shader_program("skybox.vert", "skybox.frag", allocator=perm_alloc) or_return
  shaders["post"]      = make_shader_program("post.vert",   "post.frag", allocator=perm_alloc) or_return
  shaders["billboard"] = make_shader_program("billboard.vert", "billboard.frag", allocator=perm_alloc) or_return

  sun = {
    direction = {1.0,  -1.0, 1.0, 0.0},

    color     = {1.9,  0.8,  0.6, 1.0},
    intensity = 0.8,
    ambient   = 0.1,
  }
  sun_on = true

  flashlight = {
    inner_cutoff = math.cos(math.to_radians_f32(12.5)),
    outer_cutoff = math.cos(math.to_radians_f32(17.5)),

    direction = {0.0, 0.0, -1.0, 0.0},
    position  = vec4_from_3(state.camera.position),

    color     = {0.3, 0.5,  1.0, 1.0},
    intensity = 1.0,
    ambient   = 0.1,

    attenuation = {1.0, 0.007, 0.0002, 0.0},
  }
  flashlight_on = false

  // TODO: Required right now to be more than 1 samples
  ms_frame_buffer = make_framebuffer(state.window.w, state.window.h, 2) or_return

  frame_uniforms = make_gpu_buffer(.UNIFORM, size_of(Frame_UBO), persistent = true)

  cube_map_sides := [6]string{
    TEXTURE_DIR + "skybox/right.jpg",
    TEXTURE_DIR + "skybox/left.jpg",
    TEXTURE_DIR + "skybox/top.jpg",
    TEXTURE_DIR + "skybox/bottom.jpg",
    TEXTURE_DIR + "skybox/front.jpg",
    TEXTURE_DIR + "skybox/back.jpg",
  }
  skybox = make_skybox(cube_map_sides) or_return

  gl.CreateVertexArrays(1, &empty_vao)

  init_immediate_renderer() or_return

  init_menu() or_return

  draw_debug_stats = true
  default_font = make_font("Diablo_Light.ttf", 30.0) or_return

  ok = true

  return
}

begin_drawing :: proc() {
  using state

  // This simple?
  frame := &frames[curr_frame_index]
  if frame.fence != nil {
    result := gl.ClientWaitSync(frame.fence, gl.SYNC_FLUSH_COMMANDS_BIT, max(u64))
    gl.DeleteSync(frame.fence)

    frame.fence = nil
  }
}

begin_main_pass :: proc() {
  gl.BindFramebuffer(gl.FRAMEBUFFER, state.ms_frame_buffer.id)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

  gl.Enable(gl.DEPTH_TEST)

  gl.Enable(gl.CULL_FACE)
  gl.CullFace(gl.BACK)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
}

begin_post_pass :: proc() {
  gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Clear(gl.COLOR_BUFFER_BIT)
  gl.Disable(gl.DEPTH_TEST)
}

begin_ui_pass :: proc() {
  // We draw straight to the screen in this case... maybe we want to do other stuff later
  gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))

  gl.Disable(gl.DEPTH_TEST)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

  gl.Disable(gl.CULL_FACE)
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
  using state

  // Remember to flush the remaining portion
  immediate_frame_reset()

  // And set up for next frame
  frame := &frames[curr_frame_index]
  frame.fence = gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
  curr_frame_index = (curr_frame_index + 1) % FRAMES_IN_FLIGHT

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

  container_model,_ := make_model_from_default_container()
  defer free_model(&container_model)
  positions := DEFAULT_MODEL_POSITIONS
  for pos, idx in positions {
    e := Entity{
      position = pos,
      rotation = {
        2 * f32(idx) * math.to_radians_f32(270.0),
        2 * f32(idx) * math.to_radians_f32(180.0),
        2 * f32(idx) * math.to_radians_f32(90.0),
      },
      scale = {1.0, 1.0, 1.0},
      model = &container_model,
    }

    append(&state.entities, e)
  }

  floor_model, _ := make_model()
  defer free_model(&floor_model)
  append(&state.entities, Entity{
    position = {0.0, -5.0, 0.0},
    scale    = {100.0, 0.5, 100.0},
    model    = &floor_model
  })

  helmet_model, _ := make_model_from_file("helmet/DamagedHelmet.gltf")
  defer free_model(&helmet_model)
  append(&state.entities,  Entity{
    position = {-5.0, 0.0, 5.0},
    rotation = {90.0, 90.0, 0.0},
    scale    = {1.0, 1.0, 1.0},
    model    = &helmet_model,
  })

  duck_model, _ := make_model_from_file("duck/Duck.gltf")
  defer free_model(&duck_model)
  append(&state.entities, Entity{
    position = {5.0, 0.0, 0.0},
    scale = {0.01, 0.01, 0.01},
    model = &duck_model,
  })

  grass_material,_ := make_material("grass.png", blend = .BLEND)
  grass_model,_    := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, grass_material)
  defer free_model(&grass_model)
  append(&state.entities, Entity{
    position = {0.0, -3.0, 0.0},
    scale    = {3.0, 3.0, 3.0},
    model    = &grass_model,
  })

  window_material,_ := make_material("blending_transparent_window.png", blend = .BLEND)
  window_model,_    := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, window_material)
  defer free_model(&window_model)
  append(&state.entities, Entity{
    position = {5.0,  0.0, 5.0},
    scale    = {1.0, 1.0, 1.0},
    model    = &window_model,
  })

  POINT_LIGHT_COUNT :: 5
  point_lights: [POINT_LIGHT_COUNT]Point_Light
  for i in 0..<POINT_LIGHT_COUNT-1 {
    point_lights[i].color        = {rand.float32(), rand.float32(), rand.float32(), 1.0}
    point_lights[i].attenuation  = {1.0, 0.022, 0.0019, 0.0}
    point_lights[i].intensity    = 0.8
    point_lights[i].ambient      = 0.01
  }
  point_lights[0].position.xyz = { 50.0, 5.0,  50.0}
  point_lights[1].position.xyz = {-50.0, 5.0, -50.0}
  point_lights[2].position.xyz = { 50.0, 5.0, -50.0}
  point_lights[3].position.xyz = {-50.0, 5.0,  50.0}

  point_lights[4].position.xyz = { 0.0, 10.0, 0.0}
  point_lights[4].color        = {rand.float32(), rand.float32(), rand.float32(), 1.0}
  point_lights[4].intensity    = 0.8
  point_lights[4].ambient      = 0.01
  point_lights[4].attenuation  = {1.0, 0.022, 0.0019, 0.0}

  light_material,_ := make_material("point_light.png", blend = .BLEND)
  light_model,_ := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, light_material)
  defer free_model(&light_model)

  point_depth, ok2 := make_framebuffer(1024, 1024, 1, {.DEPTH_CUBE})
  if !ok2 do return

  SHADOW_MAP_WIDTH  :: 1024 * 2
  SHADOW_MAP_HEIGHT :: 1024 * 2

  sun_depth_buffer,_ := make_framebuffer(SHADOW_MAP_WIDTH, SHADOW_MAP_HEIGHT, 1, {.DEPTH})

  state.shaders["sun_shadow"],_ = make_shader_program("direction_shadow.vert", "none.frag")

  // Clean up temp allocator from initialization... fresh for per-frame allocations
  free_all(context.temp_allocator)

  last_frame_time := time.tick_now()
  dt_s := 0.0
  for (!should_close()) {
    // Resize check
    if state.window.resized {
      // Reset
      state.window.resized = false

      ok: bool
      state.ms_frame_buffer, ok = remake_framebuffer(&state.ms_frame_buffer, state.window.w, state.window.h)

      if !ok {
        fmt.println("Window has been resized but unable to recreate multisampling framebuffer")
        state.running = false
      }
    }

    // dt and sleeping
    if (time.tick_since(last_frame_time) < TARGET_FRAME_TIME_NS) {
      time.accurate_sleep(TARGET_FRAME_TIME_NS - time.tick_since(last_frame_time))
    }

    // New dt after sleeping
    dt_s = f64(time.tick_since(last_frame_time)) / BILLION

    state.fps = 1.0 / dt_s

    state.frame_count += 1
    last_frame_time = time.tick_now()

    poll_input_state(dt_s)

    if key_pressed(.ESCAPE) {
      toggle_menu()
    }

    if key_pressed(.F1) {
      toggle_debug_stats()
    }

    switch state.mode {
    case .EDIT:
    case .GAME:
    // Update
    {
      update_game_input(dt_s)
      update_camera(&state.camera, dt_s)

      state.flashlight.position = vec4_from_3(state.camera.position)
      state.flashlight.direction = vec4_from_3(get_camera_forward(state.camera))

      for &e, idx in state.entities[:10] {
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
        orthographic    = get_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far),
        view            = get_camera_view(state.camera),
        camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
        z_near          = state.z_near,
        z_far           = state.z_far,
        debug_mode      = .NONE,

        // And the lights
        lights = {
          direction = state.sun if state.sun_on else {},
          spot      = state.flashlight if state.flashlight_on else {},
        }
      }
      for pl, idx in point_lights {
        frame_ubo.lights.points[idx] = pl
        frame_ubo.lights.points_count += 1
      }
      write_gpu_buffer_frame(state.frame_uniforms, 0, size_of(frame_ubo), &frame_ubo)
      bind_gpu_buffer_frame_range(state.frame_uniforms, .FRAME)

      // TODO: need to calc this for all shadow casting lights
      // So would be nice to do it up front and upload in light UBO
      // Or even just calculate on GPU?
      light_view := glsl.mat4LookAt({-2.0, 4.0, -1.0}, state.sun.direction.xyz, {0.0, 1.0, 0.0})
      light_proj := glsl.mat4Ortho3d(-20.0, 20.0, -20.0, 20.0, 0.1, 20.0)
      light_proj_view := light_proj * light_view

      begin_shadow_pass(sun_depth_buffer, 0, 0, SHADOW_MAP_WIDTH, SHADOW_MAP_HEIGHT)
      {
        bind_shader_program(state.shaders["sun_shadow"])
        // Sun has no position, only direction
        set_shader_uniform("light_proj_view", light_proj_view)

        for e in state.entities {
          set_shader_uniform("model", get_entity_model_mat4(e))
          draw_model(e.model^)
        }
      }

      begin_main_pass()
      {
        bind_shader_program(state.shaders["phong"])

        bind_texture(state.skybox.texture, 4)
        set_shader_uniform("skybox", 4)

        bind_texture(sun_depth_buffer.depth_target, 5)
        set_shader_uniform("light_depth", 5)
        set_shader_uniform("light_proj_view", light_proj_view)

        // Go through and draw opque entities, collect transparent entities
        transparent_entities := make([dynamic]^Entity, context.temp_allocator)
        for &e in state.entities {
          using e.model
          for mat in materials[:material_count] {
            if mat.blend == .BLEND {
              append(&transparent_entities, &e)
            } else {
              // We're good we can just draw opqque entities
              set_shader_uniform("model", get_entity_model_mat4(e))
              draw_model(e.model^)
            }
          }
        }

        // Skybox here so it is seen behind transparent objects, binds its own shader
        {
          draw_skybox(state.skybox)
        }

        // Draw point light billboards
        bind_shader_program(state.shaders["billboard"])
        for l in point_lights {
          temp := Entity{
            position = l.position.xyz,
            scale    = {1.0, 1.0, 1.0},
          }

          set_shader_uniform("model", get_entity_model_mat4(temp))
          draw_model(light_model, l.color)
        }

        // Transparent models
        bind_shader_program(state.shaders["phong"])
        {
          gl.Disable(gl.CULL_FACE)

          // Sort so that further entities get drawn first
          slice.sort_by(transparent_entities[:], proc(a, b: ^Entity) -> bool {
            da := squared_distance(a.position, state.camera.position)
            db := squared_distance(b.position, state.camera.position)
            return da > db
          })

          for e in transparent_entities {
            set_shader_uniform("model", get_entity_model_mat4(e^))
            draw_model(e.model^)
          }
        }
      }

      // Post-Processing Pass, switch to the screens framebuffer
      begin_post_pass()
      {
        bind_shader_program(state.shaders["post"])
        bind_texture(state.ms_frame_buffer.color_target, 0)
        set_shader_uniform("screen_texture", 0)

        // Hardcoded vertices in post vertex shader, but opengl requires a VAO for draw calls
        gl.BindVertexArray(state.empty_vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)
      }

      if (state.draw_debug_stats) {
        begin_ui_pass()
        draw_debug_stats()
      }
    }
    case .MENU:
      update_menu_input()
      begin_drawing()
      draw_menu()
      flush_drawing()
    }

    free_all(context.temp_allocator)
  }
}

free_state :: proc() {
  using state

  free_immediate_renderer()

  free_skybox(&skybox)

  free_gpu_buffer(&frame_uniforms)

  for _, &shader in shaders {
    free_shader_program(&shader)
  }

  glfw.DestroyWindow(window.handle)
  // glfw.Terminate() // Causing crashes?
  virtual.arena_destroy(&perm)
}

seconds_since_start :: proc() -> (seconds: f64) {
  return time.duration_seconds(time.since(state.start_time))
}

update_game_input :: proc(dt_s: f64) {
  using state

  // Don't really need the precision?
  x_delta := f32(input.mouse.curr_pos.x - input.mouse.prev_pos.x)
  y_delta := f32(input.mouse.curr_pos.y - input.mouse.prev_pos.y)

  camera.yaw   -= camera.sensitivity * x_delta
  camera.pitch -= camera.sensitivity * y_delta
  camera.pitch = clamp(camera.pitch, -89.0, 89.0)

  if key_pressed(.F) {
    flashlight_on = !flashlight_on;
  }

  input_direction: vec3
  camera_forward, camera_up, camera_right := get_camera_axes(camera)
  // Z, forward
  if key_down(.W) {
    input_direction += camera_forward
  }
  if key_down(.S) {
    input_direction -= camera_forward
  }

  // Y, vertical
  if key_down(.SPACE) {
    input_direction += camera_up
  }
  if key_down(.LEFT_CONTROL) {
    input_direction -= camera_up
  }

  // X, strafe
  if key_down(.D) {
    input_direction += camera_right
  }
  if key_down(.A) {
    input_direction -= camera_right
  }

  if mouse_scrolled_up() {
    camera.target_fov_y -= 5.0
  }
  if mouse_scrolled_down() {
    camera.target_fov_y += 5.0
  }
  camera.target_fov_y = clamp(camera.target_fov_y, 10.0, 120)

  input_direction = linalg.normalize0(input_direction)
  camera.position += input_direction * camera.move_speed * f32(dt_s)
}
