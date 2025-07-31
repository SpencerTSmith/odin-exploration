package main

import "vendor:glfw"
import "core:fmt"
import "core:math"

KEY_COUNT :: glfw.KEY_LAST + 1

Key :: enum {
  NONE,

  SPACE,
  APOSTROPHE,
  COMMA,
  MINUS,
  PERIOD,
  SLASH,
  SEMICOLON,
  EQUAL,
  LEFT_BRACKET,
  BACKSLASH,
  RIGHT_BRACKET,
  GRAVE_ACCENT,

  _0,
  _1,
  _2,
  _3,
  _4,
  _5,
  _6,
  _7,
  _8,
  _9,

  A,
  B,
  C,
  D,
  E,
  F,
  G,
  H,
  I,
  J,
  K,
  L,
  M,
  N,
  O,
  P,
  Q,
  R,
  S,
  T,
  U,
  V,
  W,
  X,
  Y,
  Z,

  ESCAPE,
  ENTER,
  TAB,
  BACKSPACE,
  INSERT,
  DELETE,
  RIGHT,
  LEFT,
  DOWN,
  UP,
  PAGE_UP,
  PAGE_DOWN,
  HOME,
  END,
  CAPS_LOCK,
  SCROLL_LOCK,
  NUM_LOCK,
  PRINT_SCREEN,
  PAUSE,

  F1,
  F2,
  F3,
  F4,
  F5,
  F6,
  F7,
  F8,
  F9,
  F10,
  F11,
  F12,

  LEFT_SHIFT,
  LEFT_CONTROL,
  LEFT_ALT,
  LEFT_SUPER,
  RIGHT_SHIFT,
  RIGHT_CONTROL,
  RIGHT_ALT,
  RIGHT_SUPER,
}

Input_Status :: enum {
  NONE,
  PRESSED,
  RELEASED,
}

// Seconds
// NOTE: Perhaps we want to be able to control the repeat rate on a case by case basis
// Be able to pass it in to the function?
INPUT_REPEAT_RATE     :: 15.0
INPUT_REPEAT_INTERVAL :: 1.0 / INPUT_REPEAT_RATE
INPUT_REPEAT_DELAY    :: 0.4

Key_Info :: struct {
  prev_status: Input_Status,
  curr_status: Input_Status,
  time_held:   f64, // Seconds
  next_repeat: f64,
}

Mouse_Info :: struct {
  prev_pos:     dvec2,
  curr_pos:     dvec2,
  delta_scroll: dvec2,
  curr_scroll:  dvec2,

  prev_left:  Input_Status,
  curr_left:  Input_Status,
  prev_right: Input_Status,
  curr_right: Input_Status,
}

Input_State :: struct {
  keys:  [Key]Key_Info,
  mouse: Mouse_Info,
}

mouse_scroll_callback :: proc "c" (window: glfw.WindowHandle, x_scroll, y_scroll: f64) {
  state_struct := cast(^State)glfw.GetWindowUserPointer(window)
  using state_struct.input.mouse

  // Just get the direction
  dir_x := math.sign(x_scroll)
  dir_y := math.sign(y_scroll)

  delta_scroll.x += dir_x
  delta_scroll.y += dir_y
}

update_input_state :: proc(dt_s: f64) {
  input := &state.input

  // Save previous state
  {
    for i in Key {
      input.keys[i].prev_status = input.keys[i].curr_status
    }

    input.mouse.prev_pos.x = input.mouse.curr_pos.x
    input.mouse.prev_pos.y = input.mouse.curr_pos.y

    input.mouse.prev_left   = input.mouse.curr_left
    input.mouse.prev_right  = input.mouse.curr_right

    input.mouse.curr_scroll += input.mouse.delta_scroll
    input.mouse.delta_scroll = {}
  }

  // Will
  glfw.PollEvents()

  input.mouse.curr_pos.x, input.mouse.curr_pos.y = glfw.GetCursorPos(state.window.handle)

  // Update mouse buttons
  {
    switch left_state := glfw.GetMouseButton(state.window.handle, glfw.MOUSE_BUTTON_LEFT); left_state {
    case glfw.PRESS: input.mouse.curr_left   = .PRESSED
    case glfw.RELEASE: input.mouse.curr_left = .RELEASED
    }
    switch right_state := glfw.GetMouseButton(state.window.handle, glfw.MOUSE_BUTTON_RIGHT); right_state {
    case glfw.PRESS: input.mouse.curr_right   = .PRESSED
    case glfw.RELEASE: input.mouse.curr_right = .RELEASED
    }
  }

  // Translate to our keys from glfw
  // NOTE: bleh implementation... iterating over many more
  // elements than nesessecary probably
  for glfw_key in 0..=glfw.KEY_LAST {
    key := glfw_key_to_internal(glfw_key)

    if key != .NONE {
      key_state := glfw.GetKey(state.window.handle, i32(glfw_key))

      switch key_state {
      case glfw.PRESS:
        input.keys[key].curr_status = .PRESSED
        input.keys[key].time_held   += dt_s
      case glfw.RELEASE:
        input.keys[key].curr_status = .RELEASED
        input.keys[key].time_held   = 0.0
        input.keys[key].next_repeat = 0.0
      }
    }
  }
}

key_released :: proc(key: Key) -> bool {
  key_info := state.input.keys[key]

  return key_info.prev_status == .PRESSED && key_info.curr_status == .RELEASED
}

key_pressed :: proc(key: Key) -> bool {
  key_info := state.input.keys[key]

  return key_info.prev_status == .RELEASED && key_info.curr_status == .PRESSED
}

key_down :: proc(key: Key) -> bool {
  key_info := state.input.keys[key]

  return key_info.curr_status == .PRESSED
}

key_up :: proc(key: Key) -> bool {
  key_info := state.input.keys[key]

  return key_info.curr_status == .RELEASED
}

key_repeated :: proc(key: Key) -> bool {
  // Reference since we need to update here?
  // TODO: Maybe move this into the update_input_state?
  key_info := &state.input.keys[key]

  if key_pressed(key) {
    state.input.keys[key].next_repeat = INPUT_REPEAT_DELAY
    return true
  }

  if key_info.time_held > key_info.next_repeat {
    key_info.next_repeat += INPUT_REPEAT_INTERVAL
    return true
  }

  return false
}

mouse_scrolled_up :: proc() -> bool {
  return state.input.mouse.delta_scroll.y > 0
}

mouse_scrolled_down :: proc() -> bool {
  return state.input.mouse.delta_scroll.y < 0
}

mouse_left_pressed :: proc() -> bool {
  mouse := state.input.mouse
  return mouse.prev_left == .RELEASED && mouse.curr_left == .PRESSED
}

mouse_right_pressed :: proc() -> bool {
  mouse := state.input.mouse
  return mouse.prev_right == .RELEASED && mouse.curr_right == .PRESSED
}

// NOTE: Do not look behind this curtain, ugly ugly ugly,
// Mostly just want to not have a bunch of glfw related code everywhere
// So translation table
@private
glfw_key_map := [glfw.KEY_LAST + 1]Key {
  glfw.KEY_SPACE         = .SPACE,
  glfw.KEY_APOSTROPHE    = .APOSTROPHE,
  glfw.KEY_COMMA         = .COMMA,
  glfw.KEY_MINUS         = .MINUS,
  glfw.KEY_PERIOD        = .PERIOD,
  glfw.KEY_SLASH         = .SLASH,
  glfw.KEY_SEMICOLON     = .SEMICOLON,
  glfw.KEY_EQUAL         = .EQUAL,
  glfw.KEY_LEFT_BRACKET  = .LEFT_BRACKET,
  glfw.KEY_BACKSLASH     = .BACKSLASH,
  glfw.KEY_RIGHT_BRACKET = .RIGHT_BRACKET,
  glfw.KEY_GRAVE_ACCENT  = .GRAVE_ACCENT,

  glfw.KEY_0             = ._0,
  glfw.KEY_1             = ._1,
  glfw.KEY_2             = ._2,
  glfw.KEY_3             = ._3,
  glfw.KEY_4             = ._4,
  glfw.KEY_5             = ._5,
  glfw.KEY_6             = ._6,
  glfw.KEY_7             = ._7,
  glfw.KEY_8             = ._8,
  glfw.KEY_9             = ._9,

  glfw.KEY_A             = .A,
  glfw.KEY_B             = .B,
  glfw.KEY_C             = .C,
  glfw.KEY_D             = .D,
  glfw.KEY_E             = .E,
  glfw.KEY_F             = .F,
  glfw.KEY_G             = .G,
  glfw.KEY_H             = .H,
  glfw.KEY_I             = .I,
  glfw.KEY_J             = .J,
  glfw.KEY_K             = .K,
  glfw.KEY_L             = .L,
  glfw.KEY_M             = .M,
  glfw.KEY_N             = .N,
  glfw.KEY_O             = .O,
  glfw.KEY_P             = .P,
  glfw.KEY_Q             = .Q,
  glfw.KEY_R             = .R,
  glfw.KEY_S             = .S,
  glfw.KEY_T             = .T,
  glfw.KEY_U             = .U,
  glfw.KEY_V             = .V,
  glfw.KEY_W             = .W,
  glfw.KEY_X             = .X,
  glfw.KEY_Y             = .Y,
  glfw.KEY_Z             = .Z,

  glfw.KEY_ESCAPE        = .ESCAPE,
  glfw.KEY_ENTER         = .ENTER,
  glfw.KEY_TAB           = .TAB,
  glfw.KEY_BACKSPACE     = .BACKSPACE,
  glfw.KEY_INSERT        = .INSERT,
  glfw.KEY_DELETE        = .DELETE,
  glfw.KEY_RIGHT         = .RIGHT,
  glfw.KEY_LEFT          = .LEFT,
  glfw.KEY_DOWN          = .DOWN,
  glfw.KEY_UP            = .UP,
  glfw.KEY_PAGE_UP       = .PAGE_UP,
  glfw.KEY_PAGE_DOWN     = .PAGE_DOWN,
  glfw.KEY_HOME          = .HOME,
  glfw.KEY_END           = .END,
  glfw.KEY_CAPS_LOCK     = .CAPS_LOCK,
  glfw.KEY_SCROLL_LOCK   = .SCROLL_LOCK,
  glfw.KEY_NUM_LOCK      = .NUM_LOCK,
  glfw.KEY_PRINT_SCREEN  = .PRINT_SCREEN,
  glfw.KEY_PAUSE         = .PAUSE,

  glfw.KEY_F1            = .F1,
  glfw.KEY_F2            = .F2,
  glfw.KEY_F3            = .F3,
  glfw.KEY_F4            = .F4,
  glfw.KEY_F5            = .F5,
  glfw.KEY_F6            = .F6,
  glfw.KEY_F7            = .F7,
  glfw.KEY_F8            = .F8,
  glfw.KEY_F9            = .F9,
  glfw.KEY_F10           = .F10,
  glfw.KEY_F11           = .F11,
  glfw.KEY_F12           = .F12,

  glfw.KEY_LEFT_SHIFT    = .LEFT_SHIFT,
  glfw.KEY_LEFT_CONTROL  = .LEFT_CONTROL,
  glfw.KEY_LEFT_ALT      = .LEFT_ALT,
  glfw.KEY_LEFT_SUPER    = .LEFT_SUPER,
  glfw.KEY_RIGHT_SHIFT   = .RIGHT_SHIFT,
  glfw.KEY_RIGHT_CONTROL = .RIGHT_CONTROL,
  glfw.KEY_RIGHT_ALT     = .RIGHT_ALT,
  glfw.KEY_RIGHT_SUPER   = .RIGHT_SUPER,
}

@private
glfw_key_to_internal :: proc(glfw_code: int) -> Key {
  return glfw_key_map[glfw_code]
}
