package main

import "core:strings"
import "core:fmt"
import "core:image"
import "core:image/png"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

Texture :: distinct u32

Pixel_Format :: enum u32 {
	R = gl.RED,
	RGB = gl.RGB,
	RGBA = gl.RGBA,
}

Texture_Bind_Location :: enum u32 {
	BIND_0 = gl.TEXTURE0,
	BIND_1 = gl.TEXTURE1,
	BIND_2 = gl.TEXTURE2,
	BIND_3 = gl.TEXTURE3,
}

make_texture :: proc {
	make_texture_default,
	make_texture_from_file,
}

// Just a black pixel
make_texture_default :: proc() -> (texture: Texture) {
	tex_id: u32

	gl.GenTextures(1, &tex_id)
	gl.BindTexture(gl.TEXTURE_2D, tex_id)
	defer gl.BindTexture(gl.TEXTURE_2D, 0)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	black_pixel: vec3 = {0, 0, 0}
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1,
		0, gl.RGB, gl.UNSIGNED_BYTE, &black_pixel);
	gl.GenerateMipmap(gl.TEXTURE_2D)

	return Texture(tex_id)
}

make_texture_from_file :: proc(file_path: string) -> (texture: Texture, ok: bool) {
	c_path := strings.unsafe_string_to_cstring(file_path)

	tex_id: u32
	ok = false

	texture_data, err := image.load(file_path, allocator = context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		fmt.eprintf("Could not load texture \"%v\", error: %v\n", file_path, err)
	} else {
		format: Pixel_Format
		switch (texture_data.channels) {
		case 1:
			format = .R
		case 3:
			format = .RGB
		case 4:
			format = .RGBA
		}

		gl.GenTextures(1, &tex_id)
		gl.BindTexture(gl.TEXTURE_2D, tex_id)
		defer gl.BindTexture(gl.TEXTURE_2D, 0)

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(texture_data.width), i32(texture_data.height),
									0, u32(format), gl.UNSIGNED_BYTE, raw_data(texture_data.pixels.buf));
		gl.GenerateMipmap(gl.TEXTURE_2D)
		ok = true
	}
	
	return Texture(tex_id), ok
}

free_texture :: proc(texture: ^Texture) {
	gl.DeleteTextures(1, cast(^u32)texture)
}

bind_texture :: proc(texture: Texture, location: Texture_Bind_Location) {
	gl.ActiveTexture(u32(location))
	gl.BindTexture(gl.TEXTURE_2D, u32(texture))
}
