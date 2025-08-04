package main

import "core:fmt"
import "core:strings"
import "core:math"
import "core:path/filepath"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

TEXTURE_DIR :: DATA_DIR + "textures" + PATH_SLASH

// TODO: Unify texture creation under 1 function group would be nice
Texture_Type :: enum {
  _2D            = 0, // Can't have 2D
  MULTISAMPLE_2D = 1,
  CUBE_MAP       = 1,
}

Texture :: struct {
  id:         u32,
  type:       Texture_Type,
  format:     Pixel_Format,
  bit_format: Internal_Pixel_Format,
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

  // Depth
  DEPTH         = gl.DEPTH_COMPONENT24,
  DEPTH_STENCIL = gl.DEPTH24_STENCIL8,

  // Non linear color spaces, diffuse only, usually
  SRGB8  = gl.SRGB8,
  SRGBA8 = gl.SRGB8_ALPHA8,
}

Material_Blend_Mode :: enum {
  OPAQUE = 0,
  BLEND,
  MASK,
}

Material :: struct {
  diffuse:   Texture,
  specular:  Texture,
  emissive:  Texture,
  shininess: f32,

  blend: Material_Blend_Mode,
}

make_material :: proc {
  make_material_from_files,
}

DIFFUSE_DEFAULT  :: "white.png"
SPECULAR_DEFAULT :: "white.png"
EMISSIVE_DEFAULT :: "black.png"

// Can either pass in nothing for a particular texture path, or pass in an empty string to use defaults
make_material_from_files :: proc(diffuse_path:   string = DIFFUSE_DEFAULT,
                                 specular_path:  string = SPECULAR_DEFAULT,
                                 emissive_path:  string = EMISSIVE_DEFAULT,
                                 shininess:      f32    = 32.0,
                                 blend: Material_Blend_Mode = .OPAQUE,
                                 in_texture_dir: bool = true) -> (material: Material, ok: bool) {
  // HACK: Quite ugly but I think this makes it a nicer interface
  // But always remember too much VOOODOO?!
  resolve_path :: proc(argument, default: string, argument_in_dir: bool) -> (resolved: string, in_texture_dir: bool) {
    if argument == "" {
      resolved       = default
      in_texture_dir = true
    } else {
      resolved       = argument
      in_texture_dir = argument_in_dir
    }

    return resolved, in_texture_dir
  }

  diffuse, diffuse_in_dir   := resolve_path(diffuse_path, DIFFUSE_DEFAULT, in_texture_dir)
  specular, specular_in_dir := resolve_path(specular_path, SPECULAR_DEFAULT, in_texture_dir)
  emissive, emissive_in_dir := resolve_path(emissive_path, EMISSIVE_DEFAULT, in_texture_dir)

  material.diffuse, ok  = make_texture(diffuse, nonlinear_color = true, in_texture_dir = diffuse_in_dir)
  if !ok {
    material.diffuse = make_texture_from_missing()
    fmt.printf("Unable to create diffuse texture \"%v\" for material, using missing\n", diffuse)
  }

  material.specular, ok  = make_texture(specular, in_texture_dir = specular_in_dir)
  if !ok {
    material.specular = make_texture_from_missing()
    fmt.printf("Unable to create specular texture \"%v\" for material, using missing\n", specular)
  }

  material.emissive, ok = make_texture(emissive, in_texture_dir = emissive_in_dir)
  if !ok {
    material.emissive = make_texture_from_missing()
    fmt.printf("Unable to create emissive texture \"%v\" for material, using missing\n", emissive)
  }

  material.shininess = shininess
  material.blend = blend
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
    bind_texture(material.diffuse,  "mat_diffuse");

    bind_texture(material.specular, "mat_specular");

    bind_texture(material.emissive, "mat_emissive");

    set_shader_uniform("mat_shininess", material.shininess)

    state.current_material = material
  }
}

make_texture :: proc {
  make_texture_from_bytes,
  make_texture_from_rawptr,
  make_texture_from_rawptr_format,
  make_texture_from_file,
  make_texture_from_missing,
}

// So we know it's missing
make_texture_from_missing :: proc() -> (texture: Texture) {
  texture, _ = make_texture_from_file("missing.png")
  return
}

make_texture_from_rawptr_format :: proc(data: rawptr, w, h: i32,
                                        format: Pixel_Format,
                                        bit_format: Internal_Pixel_Format) -> (texture: Texture, ok: bool) {
  tex_id: u32
  gl.CreateTextures(gl.TEXTURE_2D, 1, &tex_id)

  gl.TextureParameteri(tex_id, gl.TEXTURE_WRAP_S,     gl.REPEAT)
  gl.TextureParameteri(tex_id, gl.TEXTURE_WRAP_T,     gl.REPEAT)
  gl.TextureParameteri(tex_id, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
  gl.TextureParameteri(tex_id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

  mip_level := i32(math.log2(f32(max(w, h))) + 1)
  gl.TextureStorage2D(tex_id, mip_level, u32(bit_format), w, h)
  gl.TextureSubImage2D(tex_id, 0, 0, 0, i32(w), i32(h), u32(format), gl.UNSIGNED_BYTE, data);
  gl.GenerateTextureMipmap(tex_id)

  texture = {
    id         = tex_id,
    type       = ._2D,
    format     = format,
    bit_format = bit_format,
  }

  return texture, true
}

make_texture_from_rawptr :: proc(data: rawptr, w, h, channels: i32,
                                 nonlinear_color: bool = false) -> (texture: Texture, ok: bool) {
  format:   Pixel_Format
  internal: Internal_Pixel_Format
  switch channels {
  case 1:
    format = .R
    internal = .R8
  case 3:
    format = .RGB
    internal = .SRGB8 if nonlinear_color else .RGB8
  case 4:
    format = .RGBA
    internal = .SRGBA8 if nonlinear_color else .RGBA8
  }

  return make_texture_from_rawptr_format(data, w, h, format, internal)
}

make_texture_from_bytes :: proc(data: []byte, w, h, channels: i32,
                                nonlinear_color: bool = false) -> (texture: Texture, ok: bool) {
  return make_texture_from_rawptr(raw_data(data), w, h, channels, nonlinear_color)
}

make_texture_from_file :: proc(file_name: string, nonlinear_color: bool = false,
                               in_texture_dir: bool = true) -> (texture: Texture, ok: bool) {
  path := in_texture_dir ? filepath.join({TEXTURE_DIR, file_name}, context.temp_allocator) : file_name

  c_path := strings.clone_to_cstring(path, context.temp_allocator)

  w, h, channels: i32
  texture_data := stbi.load(c_path, &w, &h, &channels, 0)
  if texture_data == nil {
    fmt.eprintf("Could not load texture \"%v\"\n", path)
    return texture, false
  }
  defer stbi.image_free(texture_data)

  return make_texture_from_rawptr(texture_data, w, h, channels, nonlinear_color)
}

free_texture :: proc(texture: ^Texture) {
  gl.DeleteTextures(1, &texture.id)
}

bind_texture :: proc{
  bind_texture_slot,
  bind_texture_name,
}

bind_texture_slot :: proc(texture: Texture, slot: u32) {
  // NOTE: Just creating a copy of this struct... maybe not so good an idea?
  // just store pointers?
  if state.bound_textures[slot].id != texture.id {
    state.bound_textures[slot] = texture
    gl.BindTextureUnit(slot, texture.id)
  }
}

bind_texture_name :: proc(texture: Texture, name: string) {
  if name in state.current_shader.uniforms {
    slot := state.current_shader.uniforms[name].binding
    bind_texture_slot(texture, u32(slot))
  }
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
  gl.TextureStorage2D(cube_id, 1, gl.SRGB8, width, height)
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

alloc_texture_depth_cube :: proc(width, height: int) -> Texture {
  cube_id: u32
  gl.CreateTextures(gl.TEXTURE_CUBE_MAP, 1, &cube_id)
  gl.TextureStorage2D(cube_id, 1, gl.DEPTH_COMPONENT24, i32(width), i32(height))

  gl.TextureParameteri(cube_id, gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_EDGE)
  gl.TextureParameteri(cube_id, gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_EDGE)
  gl.TextureParameteri(cube_id, gl.TEXTURE_WRAP_R,     gl.CLAMP_TO_EDGE)
  gl.TextureParameteri(cube_id, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
  gl.TextureParameteri(cube_id, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

  texture: Texture = {
    id   = cube_id,
    type = .CUBE_MAP,
  }
  return texture
}

// For when just needing an empty texture
// TODO: Make it just take in a type and it will do it all for ya
alloc_texture :: proc(width, height: int, format: Internal_Pixel_Format, samples: int = 1) -> Texture {
  id: u32
  type: Texture_Type = .MULTISAMPLE_2D if samples > 1 else ._2D
  if samples > 1 {
    gl.CreateTextures(gl.TEXTURE_2D_MULTISAMPLE, 1, &id)
    gl.TextureStorage2DMultisample(id, i32(samples), u32(format), i32(width), i32(height), gl.TRUE)
  } else {
    gl.CreateTextures(gl.TEXTURE_2D, 1, &id)
    gl.TextureStorage2D(id, 1, u32(format), i32(width), i32(height))
  }

  texture: Texture = {
    id = id,
    type = type,
  }
  return texture
}
