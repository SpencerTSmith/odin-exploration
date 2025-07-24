package main

toggle_menu :: proc() {
  if state.mode == .MENU {
    state.mode = .PLAY
  } else {
    state.mode = .MENU
  }
}
