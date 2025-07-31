package main

import "core:math/linalg"
import "core:fmt"
import gl "vendor:OpenGL"
import "vendor:glfw"

@(private="file")
Menu :: struct {
  title_font: Font,
  item_font:  Font,
  x_cursor:   f32,
  y_cursor:   f32,
  y_stride:   f32,

  current_item: Menu_Item,
  menu_items:   [Menu_Item]Menu_Item_Info,
}

// NOTE: This might be trying to be too smart
// I mean how many options are really going to have
// Optional confirmations?
@(private="file")
Menu_Item :: enum {
  RESUME,
  TEMP_0,
  TEMP_1,
  TEMP_2,
  QUIT,
}
@(private="file")
Menu_Item_Info :: struct {
  default_message: string,
  confirm_message: string,
  ask_to_confirm:  bool,
}

@(private="file")
menu: Menu

init_menu :: proc () -> (ok: bool) {
  using menu
  title_font, ok = make_font("Diablo_Light.ttf", 90.0)
  item_font, ok  = make_font("Diablo_Light.ttf", 50.0)

  menu_items = {
    .RESUME = {"Resume", "", false},
    .TEMP_0 = {"Temp", "", false},
    .TEMP_1 = {"Temp", "", false},
    .TEMP_2 = {"Temp", "", false},
    .QUIT   = {"Quit", "Confirm Quit?", false},
  }

  return ok
}

toggle_menu :: proc() {
  menu.current_item = .RESUME
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

  if key_repeated(.DOWN) || key_repeated(.S) do advance_item(+1)
  if key_repeated(.UP)   || key_repeated(.W) do advance_item(-1)

  // FIXME: Ehh feels a bit janky
  if mouse_scrolled_up()   do advance_item(-1)
  if mouse_scrolled_down() do advance_item(+1)

  if key_pressed(.ENTER) || mouse_pressed(.LEFT) {
    #partial switch current_item {
    case .RESUME:
      toggle_menu()
    case .QUIT:
      if menu_items[.QUIT].ask_to_confirm == true {
        close_program()
      } else {
        menu_items[.QUIT].ask_to_confirm = true
      }
    }
  }

  // Reset any items asking for confirmation
  for &info, item in menu_items {
    if item != current_item do info.ask_to_confirm = false
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

  draw_item :: proc(info: Menu_Item_Info, item: Menu_Item) {
    color := WHITE
    if current_item == item {
      t := f32(linalg.cos(seconds_since_start() * 1.4))
      t *= t
      color_1 := LEARN_OPENGL_ORANGE * 0.9
      color_2 := LEARN_OPENGL_ORANGE * 1.1
      color = linalg.lerp(color_1, color_2, vec4{t, t, t, 1.0})
    }

    // Check if we should display a confirm message and that the option even has one
    text := info.default_message
    if info.ask_to_confirm && info.confirm_message != "" {
      text = info.confirm_message
      t := f32(linalg.cos(seconds_since_start() * 6))
      t *= t
      color = linalg.lerp(WHITE, color, vec4{t, t, t, 1.0})
    }

    draw_text(text, item_font, x_cursor, y_cursor,
              color, .CENTER)
     y_cursor += y_stride
  }

  for info, item in menu_items {
    draw_item(info, item)
  }

  immediate_flush()
}

