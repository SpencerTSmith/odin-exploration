package main

import "core:fmt"
import "core:strings"
import "core:image"
import "core:image/png"

import gl "vendor:OpenGL"

Texture :: distinct u32

Pixel_Format :: enum u32 {
	R =    gl.RED,
	RGB =  gl.RGB,
	RGBA = gl.RGBA,
}

// TODO(ss): Actually make sure these are true
Internal_Pixel_Format :: enum u32 {
  R8 =    gl.R8,
  RGB8 =  gl.RGB8,
  RGBA8 = gl.RGBA8,
}

Material :: struct {
	diffuse:   Texture,
	specular:  Texture,
	emission:  Texture,
	shininess: f32,
}

make_material :: proc {
	make_material_default,
	make_material_from_files,
}

make_material_default :: proc() -> (material: Material) {
	material.diffuse = make_texture()
	material.specular = make_texture()
	material.emission = make_texture()
	material.shininess = 0.0

	return
}

make_material_from_files :: proc(diffuse, specular, emission: string,
																 shininess: f32) -> (material: Material, ok: bool) {
	material.diffuse, ok  = make_texture(diffuse)
	if !ok {
		material.diffuse = make_texture()
		fmt.println("Unable to create diffuse texture for material, using default")
	}

	material.specular, ok  = make_texture(specular)
	if !ok {
		material.specular = make_texture()
		fmt.println("Unable to create specular texture for material, using default")
	}

	material.emission, ok = make_texture(emission)
	if !ok {
		material.emission = make_texture()
		fmt.println("Unable to create emission texture for material, using default")
	}

	material.shininess = shininess
	return
}

free_material :: proc(material: ^Material) {
	free_texture(&material.diffuse)
	free_texture(&material.specular)
	free_texture(&material.emission)
}

bind_material :: proc(material: Material, program: Shader_Program) {
	if state.current_material != material {
		bind_texture(material.diffuse,  0);
		bind_texture(material.specular, 1);
		bind_texture(material.emission, 2);
		set_shader_uniform(program, "material.diffuse",  0)
		set_shader_uniform(program, "material.specular", 1)
		set_shader_uniform(program, "material.emission", 2)
		set_shader_uniform(program, "material.shininess", material.shininess)

		state.current_material = material
	}
}

make_texture :: proc {
	make_texture_default,
	make_texture_from_file,
}

// Just a black pixel
make_texture_default :: proc() -> (texture: Texture) {
	tex_id: u32
	gl.CreateTextures(gl.TEXTURE_2D, 1, &tex_id)

	gl.TextureParameteri(tex_id, gl.TEXTURE_WRAP_S,     gl.REPEAT)
	gl.TextureParameteri(tex_id, gl.TEXTURE_WRAP_T,     gl.REPEAT)
	gl.TextureParameteri(tex_id, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TextureParameteri(tex_id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	black_pixel: vec3 = {0, 0, 0}
  w, h:i32 = 1,1
  gl.TextureStorage2D(tex_id, 1, gl.RGB8, w, h)
	gl.TextureSubImage2D(tex_id, 0, 0, 0, w, h, gl.RGB, gl.UNSIGNED_BYTE, &black_pixel);
	gl.GenerateTextureMipmap(tex_id)

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
		format:   Pixel_Format
    internal: Internal_Pixel_Format
		switch (texture_data.channels) {
		case 1:
			format = .R
      internal = .R8
		case 3:
			format = .RGB
      internal = .RGB8
		case 4:
			format = .RGBA
      internal = .RGBA8
		}

	  gl.CreateTextures(gl.TEXTURE_2D, 1, &tex_id)

	  gl.TextureParameteri(tex_id, gl.TEXTURE_WRAP_S,     gl.REPEAT)
	  gl.TextureParameteri(tex_id, gl.TEXTURE_WRAP_T,     gl.REPEAT)
	  gl.TextureParameteri(tex_id, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	  gl.TextureParameteri(tex_id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	  gl.TextureStorage2D(tex_id, 1, u32(internal), i32(texture_data.width), i32(texture_data.height))
	  gl.TextureSubImage2D(tex_id, 0, 0, 0, i32(texture_data.width), i32(texture_data.height), u32(format), gl.UNSIGNED_BYTE, raw_data(texture_data.pixels.buf));
	  gl.GenerateTextureMipmap(tex_id)
	
		ok = true
	}
	
	return Texture(tex_id), ok
}

free_texture :: proc(texture: ^Texture) {
	gl.DeleteTextures(1, cast(^u32)texture)
}

bind_texture :: proc(texture: Texture, location: u32) {
	gl.BindTextureUnit(location, u32(texture))
}
