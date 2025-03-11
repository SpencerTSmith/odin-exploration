package main

import "vendor:glfw"
import gl "vendor:OpenGL"

begin_frame :: proc() {
	gl.ClearColor(LEARN_OPENGL_BLUE.r, LEARN_OPENGL_BLUE.g, LEARN_OPENGL_BLUE.b, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

end_frame :: proc(window: Window) {
	glfw.SwapBuffers(window.handle)
}
