package main

import gl "vendor:OpenGL"
import "vendor:glfw"

toggle_menu :: proc() {
  switch state.mode {
  case .MENU:
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    state.mode = .PLAY
  case .PLAY:
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
    state.mode = .MENU
  }
}

update_menu_input :: proc() {
  using state
}

draw_menu :: proc() {
  gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
  gl.ClearColor(LEARN_OPENGL_BLUE.r, LEARN_OPENGL_BLUE.g, LEARN_OPENGL_BLUE.b, 1.0)
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
}
