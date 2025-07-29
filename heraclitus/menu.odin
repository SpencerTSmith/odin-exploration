package main

import "core:fmt"
import gl "vendor:OpenGL"
import "vendor:glfw"

Menu :: struct {
  title_font: Font,
  item_font:  Font,
  x_cursor:   f32,
  y_cursor:   f32,
  y_stride:   f32,

  current_item: Menu_Item,
}

Menu_Item :: enum {
  RESUME,
  QUIT,
}

Menu_Item_Strings :: [Menu_Item]string {
  .RESUME = "Resume",
  .QUIT   = "Quit",
}

@(private="file")
menu: Menu

init_menu :: proc () -> (ok: bool) {
  using menu
  title_font, ok = make_font("Diablo_Light.ttf", 90.0)
  item_font, ok  = make_font("Diablo_Light.ttf", 50.0)

  return ok
}

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
  using menu

  advance_item :: proc(step: int) {
    current_item_idx := int(current_item) + step

    if current_item_idx < 0               do current_item_idx = len(Menu_Item) - 1
    if current_item_idx >= len(Menu_Item) do current_item_idx = 0

    current_item = Menu_Item(current_item_idx)
  }

  if key_was_pressed(.DOWN) do advance_item(+1)
  if key_was_pressed(.UP)   do advance_item(-1)

  if key_was_pressed(.ENTER) {
    switch current_item {
    case .RESUME:
      toggle_menu()
    case .QUIT:
      state.running = false
    }

  }
}

draw_menu :: proc() {
  using menu

  gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
  gl.ClearColor(LEARN_OPENGL_BLUE.r, LEARN_OPENGL_BLUE.g, LEARN_OPENGL_BLUE.b, 1.0)
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

  // Should be updated everytime we call
  x_cursor = f32(state.window.w) * 0.5
  y_cursor = f32(state.window.h) * 0.2
  y_stride = item_font.line_height

  draw_text("Heraclitus", title_font, x_cursor, y_cursor, WHITE, .CENTER)
  y_cursor += y_stride * 1.7 // Big gap here

  draw_item :: proc(text: string, item: Menu_Item) {
    color := current_item == item ? LEARN_OPENGL_ORANGE : WHITE

    draw_text(text, item_font, x_cursor, y_cursor,
              color, .CENTER)
     y_cursor += y_stride
  }

  for text, item in Menu_Item_Strings {
    draw_item(text, item)
  }

  immediate_flush()
}

