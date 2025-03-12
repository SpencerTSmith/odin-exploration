package main

import "core:strings"
import "core:fmt"
import "core:image/png"

import gl "vendor:OpenGL"

Texture :: distinct u32

Pixel_Format :: enum u32 {
	RGB = gl.RGB,
	RGBA = gl.RGBA
}

make_texture :: proc(file_path: string, pixel_format: Pixel_Format) -> (texture: Texture, ok: bool) {
	c_path := strings.unsafe_string_to_cstring(file_path)

	tex_id: u32
	ok = false

	texture_data, err := png.load_from_file(file_path, allocator = context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		fmt.eprintf("Could not load texture \"%v\", error: %v\n", file_path, err)
	} else {

		gl.GenTextures(1, &tex_id)
		gl.BindTexture(gl.TEXTURE_2D, tex_id)
		defer gl.BindTexture(gl.TEXTURE_2D, 0)
		
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, i32(texture_data.width), i32(texture_data.height),
									0, u32(pixel_format), gl.UNSIGNED_BYTE, raw_data(texture_data.pixels.buf));
		gl.GenerateMipmap(gl.TEXTURE_2D)
		ok = true
	}
	
	return Texture(tex_id), ok
}

free_texture :: proc(texture: ^Texture) {
	gl.DeleteTextures(1, cast(^u32)texture)
}

bind_texture :: proc(texture: Texture, location: u32) {
	gl_enum: u32
	switch location {
	case 0: gl_enum = gl.TEXTURE0
	case 1: gl_enum = gl.TEXTURE1
	}

	gl.ActiveTexture(gl_enum)
	gl.BindTexture(gl.TEXTURE_2D, u32(texture))
}
