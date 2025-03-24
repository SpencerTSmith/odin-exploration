package main

import "core:fmt"
import "core:strings"
import "core:math"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

Texture_Type :: enum {
  D2       = 0, // Can't have 2D
  CUBE_MAP = 1,
}

Texture :: struct {
  id: u32,
  type: Texture_Type,
}

Pixel_Format :: enum u32 {
  R    = gl.RED,
  RGB  = gl.RGB,
  RGBA = gl.RGBA,
}

// TODO(ss): Actually make sure these are true
Internal_Pixel_Format :: enum u32 {
  R8    = gl.R8,
  RGB8  = gl.RGB8,
  RGBA8 = gl.RGBA8,
}

Material :: struct {
  diffuse:   Texture,
  specular:  Texture,
  emissive:  Texture,
  shininess: f32,
}

make_material :: proc {
  make_material_from_files,
}

// Can either pass in nothing for a particular texture path, or pass in an empty string to use defaults
make_material_from_files :: proc(diffuse_path:   string = "./assets/white.png",
                                 specular_path:  string = "./assets/black.png",
                                 emissive_path:  string = "./assets/black.png",
                                 shininess: f32 = 0.1) -> (material: Material, ok: bool) {
  diffuse  := diffuse_path  if diffuse_path  != "" else "./assets/white.png"
  specular := specular_path if specular_path != "" else "./assets/black.png"
  emissive := emissive_path if emissive_path != "" else "./assets/black.png"

  material.diffuse, ok  = make_texture(diffuse)
  if !ok {
    material.diffuse = make_texture_from_missing()
    fmt.printf("Unable to create diffuse texture \"%v\" for material, using missing\n", diffuse)
  }

  material.specular, ok  = make_texture(specular)
  if !ok {
    material.specular = make_texture_from_missing()
    fmt.printf("Unable to create specular texture \"%v\" for material, using missing\n", specular)
  }

  material.emissive, ok = make_texture(emissive)
  if !ok {
    material.emissive = make_texture_from_missing()
    fmt.printf("Unable to create emissive texture \"%v\" for material, using missing\n", emissive)
  }

  material.shininess = shininess
  return material, ok
}

free_material :: proc(material: ^Material) {
  free_texture(&material.diffuse)
  free_texture(&material.specular)
  free_texture(&material.emissive)
}

bind_material :: proc(material: Material) {
  assert(state.current_shader.id != 0)
  if state.current_material != material {
    bind_texture(material.diffuse,  0);
    set_shader_uniform(state.current_shader, "material.diffuse",  0)

    bind_texture(material.specular, 1);
    set_shader_uniform(state.current_shader, "material.specular", 1)

    bind_texture(material.emissive, 2);
    set_shader_uniform(state.current_shader, "material.emission", 2)

    set_shader_uniform(state.current_shader, "material.shininess", material.shininess)

    state.current_material = material
  }
}

make_texture :: proc {
  make_texture_from_file,
  make_texture_from_missing,
}

// So we know it's missing
make_texture_from_missing :: proc() -> (texture: Texture) {
  texture, _ = make_texture_from_file("./assets/missing.png")
  return
}

make_texture_from_file :: proc(file_path: string) -> (texture: Texture, ok: bool) {
  c_path := strings.unsafe_string_to_cstring(file_path)

  tex_id: u32
  ok = false

  w, h, channels: i32
  texture_data := stbi.load(c_path, &w, &h, &channels, 0)
  if texture_data != nil {
    defer stbi.image_free(texture_data)
    format:   Pixel_Format
    internal: Internal_Pixel_Format
    switch (channels) {
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

    mip_level := i32(math.log2(f32(max(w, h))) + 1)
    gl.TextureStorage2D(tex_id, mip_level, u32(internal), w, h)
    gl.TextureSubImage2D(tex_id, 0, 0, 0, i32(w), i32(h), u32(format), gl.UNSIGNED_BYTE, texture_data);
    gl.GenerateTextureMipmap(tex_id)

    ok = true
  } else do fmt.eprintf("Could not load texture \"%v\"\n", file_path)

  texture.id   = tex_id
  texture.type = .D2
  return texture, ok
}

free_texture :: proc(texture: ^Texture) {
  gl.DeleteTextures(1, &texture.id)
}

bind_texture :: proc(texture: Texture, location: u32) {
  gl.BindTextureUnit(location, texture.id)
}

// Right, left, top, bottom, back, front... or
// +x,    -x,   +y,    -y,   +z,  -z
make_texture_cube_map :: proc(file_paths: [6]string) -> (cube_map: Texture, ok: bool) {
  texture_datas: [6]rawptr

  width, height: i32
  for file_path, idx in file_paths {
    c_path := strings.unsafe_string_to_cstring(file_path)

    channels: i32 // Don't really care about this
    texture_data := stbi.load(c_path, &width, &height, &channels, 0)
    if texture_data != nil {
      texture_datas[idx] = texture_data
    } else {
      fmt.printf("Could not load %s for cubemap\n", file_path)
      return
    }
  }

  cube_id: u32
  gl.CreateTextures(gl.TEXTURE_CUBE_MAP, 1, &cube_id)
  gl.TextureStorage2D(cube_id, 1, gl.RGB8, width, height)
  gl.TextureParameteri(cube_id, gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_EDGE)
  gl.TextureParameteri(cube_id, gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_EDGE)
  gl.TextureParameteri(cube_id, gl.TEXTURE_WRAP_R,     gl.CLAMP_TO_EDGE)
  gl.TextureParameteri(cube_id, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
  gl.TextureParameteri(cube_id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

  for texture_data, face in texture_datas {
    gl.TextureSubImage3D(cube_id, 0, 0, 0, i32(face), width, height, 1, gl.RGB, gl.UNSIGNED_BYTE, texture_data)
    stbi.image_free(texture_data)
  }

  ok = true
  cube_map.id   = cube_id
  cube_map.type = .CUBE_MAP
  return cube_map, ok
}
