package main

import "core:path/filepath"
import "core:log"
import "core:strings"
import "core:math"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"


// TODO: Unify texture creation under 1 function group would be nice
Texture_Type :: enum {
  NONE,
  _2D,
  CUBE,
  CUBE_ARRAY,
}

Sampler_Config :: enum {
  NONE,
  REPEAT_TRILINEAR,
  REPEAT_LINEAR,
  CLAMP_LINEAR,
}

Texture :: struct {
  id:      u32,
  type:    Texture_Type,
  width:   int,
  height:  int,
  samples: int, // Only for multisampled textures, 0 if not
  depth:   int, // Only for array textures, 0 if not
  format:  Pixel_Format,
  sampler: Sampler_Config,
}

Pixel_Format :: enum u32 {
  NONE,
  R8,
  RGB8,
  RGBA8,

  // Non linear color spaces, diffuse only, usually
  SRGB8,
  SRGBA8,

  RGBA16F,

  // Depth
  DEPTH32,
  DEPTH24_STENCIL8,
}

Material_Blend_Mode :: enum {
  OPAQUE = 0,
  BLEND,
  MASK,
}

Material :: struct {
  diffuse:   Texture_Handle,
  specular:  Texture_Handle,
  emissive:  Texture_Handle,
  normal:    Texture_Handle,
  shininess: f32,

  blend: Material_Blend_Mode,
}

make_material :: proc {
  make_material_from_files,
}

DIFFUSE_DEFAULT  :: "white.png"
SPECULAR_DEFAULT :: "black.png"
EMISSIVE_DEFAULT :: "black.png"
NORMAL_DEFAULT   :: "flat_normal.png"

// Can either pass in nothing for a particular texture path, or pass in an empty string to use defaults
make_material_from_files :: proc(diffuse_path:   string = DIFFUSE_DEFAULT,
                                 specular_path:  string = SPECULAR_DEFAULT,
                                 emissive_path:  string = EMISSIVE_DEFAULT,
                                 normal_path:    string = NORMAL_DEFAULT,
                                 shininess:      f32    = 32.0,
                                 blend: Material_Blend_Mode = .OPAQUE,
                                 in_texture_dir: bool = false) -> (material: Material, ok: bool) {
  // HACK: Quite ugly but I think this makes it a nicer interface
  // But always remember too much VOOODOO?!
  resolve_path :: proc(argument, default: string, argument_in_dir: bool) -> (resolved: string, in_texture_dir: bool) {
    if argument == "" || argument == default {
      resolved       = default
      in_texture_dir = true
    } else {
      resolved       = argument
      in_texture_dir = argument_in_dir
    }

    return resolved, in_texture_dir
  }

  diffuse,  diffuse_in_dir  := resolve_path(diffuse_path,  DIFFUSE_DEFAULT,  in_texture_dir)
  specular, specular_in_dir := resolve_path(specular_path, SPECULAR_DEFAULT, in_texture_dir)
  emissive, emissive_in_dir := resolve_path(emissive_path, EMISSIVE_DEFAULT, in_texture_dir)
  normal,   normal_in_dir   := resolve_path(normal_path,   NORMAL_DEFAULT,   in_texture_dir)

  material.diffuse, ok  = load_texture(diffuse, nonlinear_color = true, in_texture_dir = diffuse_in_dir)
  if !ok {
    material.diffuse,_ = load_texture("missing.png")
    log.errorf("Unable to create diffuse texture \"%v\" for material, using missing", diffuse)
  }

  material.specular, ok  = load_texture(specular, in_texture_dir = specular_in_dir)
  if !ok {
    material.specular,_ = load_texture("missing.png")
    log.errorf("Unable to create specular texture \"%v\" for material, using missing", specular)
  }

  material.emissive, ok = load_texture(emissive, in_texture_dir = emissive_in_dir)
  if !ok {
    material.emissive,_ = load_texture("missing.png")
    log.errorf("Unable to create emissive texture \"%v\" for material, using missing", emissive)
  }

  material.normal, ok = load_texture(normal, in_texture_dir = normal_in_dir)
  if !ok {
    material.normal,_ = load_texture("missing.png")
    log.errorf("Unable to create normal texture \"%v\" for material, using missing", normal)
  }

  material.shininess = shininess
  material.blend = blend
  return material, ok
}


free_material :: proc(material: ^Material) {
  diffuse  := get_texture(material.diffuse)
  specular := get_texture(material.specular)
  emissive := get_texture(material.emissive)

  free_texture(diffuse)
  free_texture(specular)
  free_texture(emissive)
}

bind_material :: proc(material: Material) {
  assert(state.current_shader.id != 0)

  if state.current_material != material {
    diffuse  := get_texture(material.diffuse)
    specular := get_texture(material.specular)
    emissive := get_texture(material.emissive)
    normal   := get_texture(material.normal)

    bind_texture(diffuse^,  "mat_diffuse");
    bind_texture(specular^, "mat_specular");
    bind_texture(emissive^, "mat_emissive");
    bind_texture(normal^,   "mat_normal");

    set_shader_uniform("mat_shininess", material.shininess)

    state.current_material = material
  }
}

make_texture :: proc {
  make_texture_from_data,
  make_texture_from_file,
  make_texture_from_missing,
}

// So we know it's missing
make_texture_from_missing :: proc() -> (texture: Texture) {
  texture, _ = make_texture_from_file("missing.png")
  return
}

free_texture :: proc(texture: ^Texture) {
  if texture != nil {
    gl.DeleteTextures(1, &texture.id)
  }
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

// First value is the internal format and the second is the logical format
// Ie you pass the first to TextureStorage and the second to TextureSubImage
@(private="file")
gl_pixel_format_table := [Pixel_Format][2]u32 {
  .NONE  = {0,        0},
  .R8    = {gl.R8,    gl.RED},
  .RGB8  = {gl.RGB8,  gl.RGB},
  .RGBA8 = {gl.RGBA8, gl.RGBA},

  // Non linear color spaces, diffuse only, usually
  .SRGB8  = {gl.SRGB8,        gl.RGB},
  .SRGBA8 = {gl.SRGB8_ALPHA8, gl.RGBA},

  .RGBA16F = {gl.RGBA16F, gl.RGBA},

  // Depth sturf
  .DEPTH32          = {gl.DEPTH_COMPONENT32, gl.DEPTH_COMPONENT},
  .DEPTH24_STENCIL8 = {gl.DEPTH24_STENCIL8,  gl.DEPTH_STENCIL},
}

@(private="file")
gl_texture_type_table := [Texture_Type]u32 {
  .NONE       = 0,
  ._2D        = gl.TEXTURE_2D,
  .CUBE       = gl.TEXTURE_CUBE_MAP,
  .CUBE_ARRAY = gl.TEXTURE_CUBE_MAP_ARRAY,
}


alloc_texture :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Config,
                      width, height: int, samples: int = 0, array_depth: int = 0) -> (texture: Texture) {
  assert(width > 0 && height > 0)

  gl_internal := gl_pixel_format_table[format][0]
  gl_type     := gl_texture_type_table[type]

  if samples > 0 {
    assert(type == ._2D) // HACK: Only 2D textures can be multisampled for now
    gl_type = gl.TEXTURE_2D_MULTISAMPLE
  }

  gl.CreateTextures(gl_type, 1, &texture.id)

  mip_level: i32 = 1
  if sampler == .REPEAT_TRILINEAR {
    mip_level = i32(math.log2(f32(max(width, height))) + 1)
  }

  switch type {
  case .NONE:
    log.error("Texture type cannont be none")
  case ._2D: fallthrough;
  case .CUBE:
    if samples > 0 {
      assert(type == ._2D)
      gl.TextureStorage2DMultisample(texture.id, i32(samples), gl_internal, i32(width), i32(height), gl.TRUE)
    } else {
      gl.TextureStorage2D(texture.id, mip_level, gl_internal, i32(width), i32(height))
    }
  case .CUBE_ARRAY:
    assert(array_depth > 0)
    // NOTE: Texture storage 3D takes the 'true' number of layers
    // ie for cube maps the array length needs to be multiplied by 6.
    cube_depth := array_depth * 6
    gl.TextureStorage3D(texture.id, mip_level, gl_internal, i32(width), i32(height), i32(cube_depth))
  }

  if samples == 0 {
    // Only non multisampling textures can have sampler parameters I believe?
    // HACK: This sucks... might just separate samplers conceptually from textures?
    switch sampler {
    case .NONE: // Nothin'
    case .REPEAT_TRILINEAR:
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_S,     gl.REPEAT)
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_T,     gl.REPEAT)
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_R,     gl.REPEAT)
      gl.TextureParameteri(texture.id, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
      gl.TextureParameteri(texture.id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    case .REPEAT_LINEAR:
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_S,     gl.REPEAT)
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_T,     gl.REPEAT)
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_R,     gl.REPEAT)
      gl.TextureParameteri(texture.id, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
      gl.TextureParameteri(texture.id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    case .CLAMP_LINEAR:
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_EDGE)
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_EDGE)
      gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_R,     gl.CLAMP_TO_EDGE)
      gl.TextureParameteri(texture.id, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
      gl.TextureParameteri(texture.id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    }
  }

  texture.width   = width
  texture.height  = height
  texture.type    = type
  texture.format  = format
  texture.sampler = sampler
  texture.samples = samples
  texture.depth   = array_depth

  return texture
}

make_texture_from_data :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Config,
                               datas: []rawptr, width, height: int, samples: int = 0) -> (texture: Texture) {
  texture = alloc_texture(type, format, sampler, width, height, samples)

  if datas != nil {
    gl_format := gl_pixel_format_table[format][1]
    switch type {
    case .NONE:
      log.error("Texture type cannot be none\n")
    case ._2D:
      assert(len(datas) == 1)
      gl.TextureSubImage2D(texture.id, 0, 0, 0, i32(width), i32(height), gl_format, gl.UNSIGNED_BYTE, datas[0]);
    case .CUBE:
      if type == .CUBE {
        for data, face in datas {
          gl.TextureSubImage3D(texture.id, 0, 0, 0, i32(face), i32(width), i32(height), 1, gl_format, gl.UNSIGNED_BYTE, data);
        }
      }
    case .CUBE_ARRAY:
      assert(false) // What da?
    }

    gl.GenerateTextureMipmap(texture.id)
  }

  return texture
}

format_for_channels :: proc(channels: int, nonlinear_color: bool = false) -> Pixel_Format {
  format: Pixel_Format
  switch channels {
  case 1:
    format = .R8
  case 3:
    format = .SRGB8 if nonlinear_color else .RGB8
  case 4:
    format = .SRGBA8 if nonlinear_color else .RGBA8
  }

  return format
}

get_image_data :: proc(file_path: string) -> (data: rawptr, width, height, channels: int) {
  c_path := strings.clone_to_cstring(file_path, context.temp_allocator)

  w, h, c: i32
  data = stbi.load(c_path, &w, &h, &c, 0)

  if data == nil {
    log.errorf("Could not load texture \"%v\"\n", file_path)
    return nil, 0, 0, 0
  }

  width    = int(w)
  height   = int(h)
  channels = int(c)
  return data, width, height, channels
}

// Right, left, top, bottom, back, front... or
// +x,    -x,   +y,    -y,   +z,  -z
make_texture_cube_map :: proc(file_paths: [6]string, in_texture_dir: bool = true) -> (cube_map: Texture, ok: bool) {
  datas: [6]rawptr
  width, height, channels: int
  for file_name, idx in file_paths {
    path := filepath.join({TEXTURE_DIR, file_name}, context.temp_allocator) if in_texture_dir else file_name

    data, w, h, c := get_image_data(path)
    if data == nil {
      log.errorf("Could not load %v for cubemap\n", path)
      return cube_map, false
    }

    // NOTE: these should all be the same
    width  = w
    height = h
    channels = c

    datas[idx] = data
  }

  format := format_for_channels(channels, true)

  cube_map = make_texture_from_data(.CUBE, format, .CLAMP_LINEAR, datas[:], width, height)

  // Clean up
  for data in datas {
    stbi.image_free(data)
  }

  return cube_map, true
}

make_texture_from_file :: proc(file_name: string, nonlinear_color: bool = false) -> (texture: Texture, ok: bool) {

  data, w, h, channels := get_image_data(file_name)
  if data == nil {
    log.errorf("Could not load texture \"%v\"\n", file_name)
    return texture, false
  }
  defer stbi.image_free(data)

  format := format_for_channels(channels, nonlinear_color)

  texture = make_texture_from_data(._2D, format, .REPEAT_TRILINEAR, {data}, w, h)

  return texture, true
}
