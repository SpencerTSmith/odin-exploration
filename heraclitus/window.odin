package main

import "core:fmt"

import gl "vendor:OpenGL"
import "vendor:glfw"

WINDOW_DEFAULT_TITLE :: "Heraclitus"
WINDOW_DEFAULT_W :: 1280 * 1.5
WINDOW_DEFAULT_H :: 720 * 1.5

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
