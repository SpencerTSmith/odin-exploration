package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "core:time"
import "core:slice"
import "core:log"

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

POINT_SHADOW_MAP_SIZE  :: 512 * 2
SUN_SHADOW_MAP_SIZE    :: 512 * 8

Program_Mode :: enum {
  GAME,
  MENU,
  EDIT,
}

Frame_Info :: struct {
  fence: gl.sync_t
}

State :: struct {
  running:            bool,
  mode:               Program_Mode,

  gl_is_initialized:  bool,

  window:             Window,

  perm:               virtual.Arena,
  perm_alloc:         mem.Allocator,

  camera:             Camera,

  entities:           [dynamic]Entity,
  point_lights:       [dynamic]Point_Light,

  start_time:         time.Time,

  hdr_ms_buffer:      Framebuffer,
  post_buffer:        Framebuffer,
  ping_pong_buffers:  [2]Framebuffer,

  point_depth_buffer: Framebuffer,

  fps:                f64,
  frame_count:        uint,
  frames:             [FRAMES_IN_FLIGHT]Frame_Info,
  curr_frame_index:   int,

  clear_color:        vec3,

  z_near:             f32,
  z_far:              f32,

  sun:                Direction_Light,
  sun_on:             bool,
  sun_depth_buffer:   Framebuffer,

  flashlight:         Spot_Light,
  flashlight_on:      bool,

  point_lights_on:    bool,

  // Could maybe replace this but this makes it easier to add them
  shaders:            map[string]Shader_Program,

  skybox:             Skybox,

  frame_uniforms:     GPU_Buffer,

  // TODO: Maybe these should be pointers and not copies
  current_shader:     Shader_Program,
  current_material:   Material,
  bound_textures:     [16]Texture,

  // NOTE: Needed to make draw calls, even if not using one
  empty_vao:          u32,

  input:              Input_State,

  draw_debug:   bool,
  default_font:       Font,

  bloom_on:           bool,

  input_direction:    vec3,
}

init_state :: proc() -> (ok: bool) {
  using state
  start_time = time.now()

  if glfw.Init() != glfw.TRUE {
    log.fatal("Failed to initialize GLFW")
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
    log.fatal("Failed to create GLFW window")
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
  gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

  gl.Enable(gl.STENCIL_TEST)
  gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)

  gl_is_initialized = true

  err := virtual.arena_init_growing(&perm)
  if err != .None {
    log.fatal("Failed to create permanent arena")
    return
  }
  perm_alloc = virtual.arena_allocator(&perm)

  init_assets()

  camera = {
    sensitivity  = 0.2,
    yaw          = 270.0,
    move_speed   = 8.0,
    position     = {0.0, 0.0, 5.0},
    curr_fov_y   = 90.0,
    target_fov_y = 90.0,
    aabb         = {{-1.0, -1.0, -1.0}, {1.0, 1.0, 1.0}}
  }

  entities     = make([dynamic]Entity, perm_alloc)
  point_lights = make([dynamic]Point_Light, perm_alloc)

  running = true

  z_near = 0.1
  z_far  = 1000.0

  shaders = make(map[string]Shader_Program, allocator=perm_alloc)

  shaders["phong"]         = make_shader_program("simple.vert", "phong.frag",  allocator=perm_alloc) or_return
  shaders["skybox"]        = make_shader_program("skybox.vert", "skybox.frag", allocator=perm_alloc) or_return
  shaders["resolve_hdr"]   = make_shader_program("to_screen.vert", "resolve_hdr.frag", allocator=perm_alloc) or_return
  shaders["billboard"]     = make_shader_program("billboard.vert", "billboard.frag", allocator=perm_alloc) or_return
  shaders["sun_depth"]     = make_shader_program("direction_shadow.vert", "direction_shadow.frag", allocator=perm_alloc) or_return
  shaders["point_shadows"] = make_shader_program("point_shadows.vert", "point_shadows.frag", allocator=perm_alloc) or_return
  shaders["gaussian"]      = make_shader_program("to_screen.vert", "gaussian.frag", allocator=perm_alloc) or_return
  shaders["get_bright"]    = make_shader_program("to_screen.vert", "get_bright_spots.frag", allocator=perm_alloc) or_return

  sun = {
    direction = {-0.5, -1.0,  0.7},
    color     = { 0.8,  0.7,  0.6, 1.0},
    intensity = 1.0,
    ambient   = 0.05,
  }
  sun.direction = linalg.normalize(state.sun.direction)
  sun_on = false

  flashlight = {

    direction = {0.0, 0.0, -1.0},
    position  = state.camera.position,

    color     = {0.3, 0.8,  1.0, 1.0},

    radius    = 50.0,
    intensity = 1.0,
    ambient   = 0.001,

    inner_cutoff = math.cos(math.to_radians_f32(12.5)),
    outer_cutoff = math.cos(math.to_radians_f32(17.5)),
  }
  flashlight_on = false

  SAMPLES :: 4
  hdr_ms_buffer = make_framebuffer(state.window.w, state.window.h, SAMPLES, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return

  post_buffer = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .HDR_COLOR, .DEPTH_STENCIL}) or_return

  ping_pong_buffers[0] = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return
  ping_pong_buffers[1] = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return

  point_depth_buffer = make_framebuffer(POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE, array_depth=MAX_POINT_LIGHTS, attachments={.DEPTH_CUBE_ARRAY}) or_return

  frame_uniforms = make_gpu_buffer(.UNIFORM, size_of(Frame_UBO), persistent = true)

  cube_map_sides := [6]string{
    "skybox/right.jpg",
    "skybox/left.jpg",
    "skybox/top.jpg",
    "skybox/bottom.jpg",
    "skybox/front.jpg",
    "skybox/back.jpg",
  }
  skybox = make_skybox(cube_map_sides) or_return

  gl.CreateVertexArrays(1, &empty_vao)

  init_immediate_renderer() or_return

  init_menu() or_return

  draw_debug = true
  default_font = make_font("Diablo_Light.ttf", 30.0) or_return

  return true
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

  clear := WHITE * 0.2
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[0].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[1].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.post_buffer.id,          gl.COLOR, 0, raw_data(&clear))
}

begin_main_pass :: proc() {
  gl.BindFramebuffer(gl.FRAMEBUFFER, state.hdr_ms_buffer.id)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

  gl.Enable(gl.DEPTH_TEST)

  gl.Enable(gl.CULL_FACE)
  gl.CullFace(gl.BACK)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
}

begin_post_pass :: proc() {
  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Disable(gl.DEPTH_TEST)

  clear := BLACK
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[0].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[1].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.post_buffer.id,          gl.COLOR, 0, raw_data(&clear))
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
begin_shadow_pass :: proc(framebuffer: Framebuffer) {
  assert(framebuffer.depth_target.id > 0)
  gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.id)

  x := 0
  y := 0

  width  := framebuffer.depth_target.width
  height := framebuffer.depth_target.height

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
  logger := log.create_console_logger()
  context.logger = logger
  defer log.destroy_console_logger(logger)

  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    defer {
      if len(track.allocation_map) > 0 {
        log.errorf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
          log.errorf("- %v bytes @ %v\n", entry.size, entry.location)
        }
      }
      if len(track.bad_free_array) > 0 {
        log.errorf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
          log.errorf("- %p @ %v\n", entry.memory, entry.location)
        }
      }
      mem.tracking_allocator_destroy(&track)
    }
  }

  if !init_state() do return
  defer free_state()

  duck1 := make_entity("duck/Duck.gltf", position={5.0, 5.0, -5.0})
  append(&state.entities, duck1)

  duck2 := make_entity("duck/Duck.gltf", position={5.0, 5.0, -5.0})
  append(&state.entities, duck2)

  // helmet := make_entity("helmet/DamagedHelmet.gltf", position={-5.0, 5.0, 0.0})
  // append(&state.entities, helmet)
  //
  // helmet2 := make_entity("helmet2/SciFiHelmet.gltf", position={5.0, 5.0, 0.0})
  // append(&state.entities, helmet2)
  //
  // guitar := make_entity("guitar/scene.gltf", position={5.0, 10.0, 0.0}, scale={0.01, 0.01, 0.01})
  // append(&state.entities, guitar)

  // sponza := make_entity("sponza/Sponza.gltf", scale={2.0, 2.0, 2.0})
  // append(&state.entities, sponza)

  // floor := make_entity("", position={0, -4, 0}, scale={1000.0, 1.0, 1000.0})
  // append(&state.entities, floor)

  { // Light placement
    spacing := 15
    bounds  := 3
    for x in 0..<bounds {
      for z in 0..<bounds {
        x0 := (x - bounds/2) * spacing
        z0 := (z) * spacing

        append(&state.point_lights, Point_Light{
          position  = {f32(x0), 10.0, f32(z0)},
          color     = {rand.float32() * 15.0, rand.float32() * 15.0, rand.float32() * 15.0, 1.0},
          intensity = 1.0,
          ambient   = 0.001,
          radius    = 20,
        })
      }
    }
  }


  light_material,_ := make_material("point_light.png", blend=.BLEND, in_texture_dir=true)
  light_model,_ := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, light_material)
  defer free_model(&light_model)

  sun_depth_buffer,_ := make_framebuffer(SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE, attachments={.DEPTH})

  // Clean up temp allocator from initialization... fresh for per-frame allocations
  free_all(context.temp_allocator)

  last_frame_time := time.tick_now()
  dt_s := 0.0
  for (!should_close()) {
    // Resize check
    if state.window.resized { resize_window() }

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
      state.draw_debug = !state.draw_debug
    }

    if key_pressed(.TAB) {
      state.mode = .EDIT if state.mode == .GAME else .GAME
    }

    if key_pressed(.L) {
      state.sun_on = !state.sun_on
    }
    if key_pressed(.P) {
      state.point_lights_on = !state.point_lights_on
    }

    if key_pressed(.B) {
      state.bloom_on = !state.bloom_on
    }

    intersect_color := BLUE

    minkowskis := make([dynamic]AABB, context.temp_allocator)

    // 'Simulate' (not really doing much right now) if in game mode
    if state.mode == .GAME {
      update_game_input(dt_s)
      update_camera(&state.camera, dt_s)
      state.flashlight.position  = state.camera.position
      state.flashlight.direction = get_camera_forward(state.camera)

      // Simulate camera collision
      // cam_aabb := camera_world_aabb(state.camera)
      for &e in state.entities {
        entity_aabb := entity_world_aabb(e)

        for &o in state.entities {
          if &o == &e { continue } // Same entity
          other_aabb := entity_world_aabb(o)

          mink := aabb_minkowski_difference(entity_aabb, other_aabb)
          append(&minkowskis, mink)
        }


        // if aabbs_intersect(cam_aabb, entity_aabb) {
        //   intersect_color = RED
        //   // state.camera.position = state.camera.prev_pos
        // }
      }

      seconds := seconds_since_start()
      state.entities[0].position.x += 2.0 * f32(dt_s) * f32(math.sin(.5 * math.PI * seconds))
      state.entities[0].position.y += 2.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds))
      state.entities[0].position.z += 2.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds))

      state.entities[0].rotation.y += 4 * cast(f32) seconds * cast(f32) dt_s

      // Update scene objects
      if state.point_lights_on {
        for &pl in state.point_lights {
          pl.position.x += 2.0 * f32(dt_s) * f32(math.sin(.5 * math.PI * seconds))
          pl.position.y += 2.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds))
          pl.position.z += 2.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds))
        }
      }
    }

    // Frame sync
    begin_drawing()

    //
    // Update frame uniform
    //

    projection := get_camera_perspective(state.camera)
    view       := get_camera_view(state.camera)
    frame_ubo: Frame_UBO = {
      projection      = projection,
      view            = view,
      proj_view       = projection * view,
      orthographic    = get_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far),
      camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
      z_near          = state.z_near,
      z_far           = state.z_far,
      debug_mode      = .NONE,

      // And the lights
      lights = {
        direction = direction_light_uniform(state.sun) if state.sun_on else {},
        spot      = spot_light_uniform(state.flashlight) if state.flashlight_on else {},
      }
    }

    if state.point_lights_on {
      for pl, idx in state.point_lights {
        if idx >= MAX_POINT_LIGHTS {
          log.error("TOO MANY POINT LIGHTS!")
        } else {
          frame_ubo.lights.points[idx] = point_light_uniform(pl)
          frame_ubo.lights.points_count += 1
        }
      }
    }
    write_gpu_buffer_frame(state.frame_uniforms, 0, size_of(frame_ubo), &frame_ubo)
    bind_gpu_buffer_frame_range(state.frame_uniforms, .FRAME)

    // What to draw based on mode
    switch state.mode {
    case .EDIT:
    case .GAME:
      if state.sun_on {
        begin_shadow_pass(sun_depth_buffer)
        {
          bind_shader_program(state.shaders["sun_depth"])

          for e in state.entities {
            draw_entity(e)
          }
        }
      }

      if state.point_lights_on {
        begin_shadow_pass(state.point_depth_buffer)
        {
          bind_shader("point_shadows")

          instances := int(6 * frame_ubo.lights.points_count)
          for e in state.entities {
            draw_entity(e, instances=instances)
          }
        }
      }

      begin_main_pass()
      {
        bind_shader_program(state.shaders["phong"])

        if state.sun_on {
          bind_texture(state.skybox.texture, "skybox")
        } else {
          bind_texture({}, "skybox")
        }

        bind_texture(sun_depth_buffer.depth_target, "sun_shadow_map")
        bind_texture(state.point_depth_buffer.depth_target, "point_light_shadows")

        // Go through and draw opque entities, collect transparent entities
        transparent_entities := make([dynamic]^Entity, context.temp_allocator)
        for &e in state.entities {
          if entity_has_transparency(e) {
              append(&transparent_entities, &e)
              continue
          }

          // We're good we can just draw opqque entities
          draw_entity(e)
        }

        // Skybox here so it is seen behind transparent objects, binds its own shader
        if state.sun_on {
          draw_skybox(state.skybox)
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
            draw_entity(e^)
          }
        }

        if state.point_lights_on {
          // Draw point light billboards
          bind_shader_program(state.shaders["billboard"])
          for l in state.point_lights {
            temp := Entity{
              position = l.position.xyz,
              scale    = {1.0, 1.0, 1.0},
            }

            set_shader_uniform("model", entity_model_mat4(temp))
            draw_model(light_model, l.color)
          }
        }

        if state.draw_debug {
          // Draw entity aabbs
          for e in state.entities {
            draw_aabb(entity_world_aabb(e))
          }

          // Draw camera aabb
          // draw_aabb(camera_world_aabb(state.camera), intersect_color)

          origin_box: AABB = {
            min = {-0.125, -0.125, -0.125},
            max = { 0.125,  0.125,  0.125}
          }
          intersect_origin_color := WHITE
          for m in minkowskis[:1] {

            if aabb_intersect_point(m, {0,0,0}) {
              intersect_origin_color = BLUE
            }

            draw_aabb(m, CORAL)
          }
          draw_aabb(origin_box, intersect_origin_color)

        }
      }

      //
      // Post-Processing Pass
      //
      begin_post_pass()
      {
        // Resolve multi-sampling buffer to ping pong as we will then sample this into the post buffer
        gl.BlitNamedFramebuffer(state.hdr_ms_buffer.id, state.ping_pong_buffers[0].id,
          0, 0, cast(i32) state.hdr_ms_buffer.color_targets[0].width, cast(i32) state.hdr_ms_buffer.color_targets[0].height,
          0, 0, cast(i32) state.ping_pong_buffers[0].color_targets[0].width, cast(i32) state.ping_pong_buffers[0].color_targets[0].height,
          gl.COLOR_BUFFER_BIT,
          gl.LINEAR)

        if state.bloom_on {
          // Now collect bright spots
          bind_framebuffer(state.post_buffer)
          bind_shader("get_bright")
          bind_texture(state.ping_pong_buffers[0].color_targets[0], "image")
          gl.BindVertexArray(state.empty_vao)
          gl.DrawArrays(gl.TRIANGLES, 0, 6)

          // Now do da blur
          bind_shader("gaussian")
          bind_texture(state.post_buffer.color_targets[1], "image")
          bind_framebuffer(state.ping_pong_buffers[0])

          BLOOM_GAUSSIAN_COUNT :: 10

          horizontal := false

          for i in 0..<BLOOM_GAUSSIAN_COUNT {
            set_shader_uniform("horizontal", horizontal)
            gl.BindVertexArray(state.empty_vao)
            gl.DrawArrays(gl.TRIANGLES, 0, 6)

            horizontal = !horizontal
            bind_texture(state.ping_pong_buffers[int(!horizontal)].color_targets[0], "image")
            bind_framebuffer(state.ping_pong_buffers[int(horizontal)])
          }
        }

        // Resolve hdr (with bloom) to backbuffer
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        bind_shader_program(state.shaders["resolve_hdr"])
        bind_texture(state.post_buffer.color_targets[0], "screen_texture")
        bind_texture(state.ping_pong_buffers[0].color_targets[0], "bloom_blur")

        set_shader_uniform("exposure", f32(0.5))

        // Hardcoded vertices in post vertex shader, but opengl requires a VAO for draw calls
        gl.BindVertexArray(state.empty_vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)
      }

      // immediate_quad({1800, 100}, 300, 300, uv0 = {1.0, 1.0}, uv1={0.0, 0.0}, texture=state.post_buffer.color_targets[1])
      // immediate_quad({1800, 100}, 800, 800, uv0 = {1.0, 1.0}, uv1={0.0, 0.0}, texture=state.ping_pong_buffers[0].color_targets[0])

      // immediate_line({1000, 900}, {500, 400}, BLUE)

      if state.draw_debug {
        begin_ui_pass()
        draw_debug_stats()
      }
    case .MENU:
      update_menu_input()
      begin_drawing()
      draw_menu()
    }

    // Frame sync, swap backbuffers
    flush_drawing()

    // Free any temp allocations
    free_all(context.temp_allocator)
  }
}

free_state :: proc() {
  using state

  free_immediate_renderer()

  free_assets()

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
    flashlight_on = !flashlight_on
  }

  input_direction = 0.0

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
}
