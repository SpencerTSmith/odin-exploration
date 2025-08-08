package main

import "core:hash"
import "core:path/filepath"
import "core:log"

DATA_DIR    :: "data" + PATH_SLASH
MODEL_DIR   :: DATA_DIR + "models"   + PATH_SLASH
TEXTURE_DIR :: DATA_DIR + "textures" + PATH_SLASH

Model_Handle   :: distinct u32
Texture_Handle :: distinct u32

Assets :: struct {
  model_catalog:   map[Model_Handle]Model,
  texture_catalog: map[Texture_Handle]Texture,
}

@(private="file")
assets: Assets

init_assets :: proc() {
  assets.model_catalog   = make(map[Model_Handle]Model, state.perm_alloc)
  assets.texture_catalog = make(map[Texture_Handle]Texture, state.perm_alloc)
}

free_assets :: proc() {
  for _, &model in assets.model_catalog {
    free_model(&model)
  }

  for _, &texture in assets.texture_catalog {
    free_texture(&texture)
  }
}

hash_name :: proc(name: string) -> u32 {
  return hash.crc32(transmute([]byte) name)
}

// NOTE: Could maybe be consolidated? Doing the same thing basically for all...

load_model :: proc(name: string) -> (handle: Model_Handle, ok: bool) {
  path := filepath.join({MODEL_DIR, name}, context.temp_allocator)

  handle = cast(Model_Handle) hash_name(path)

  // Already loaded
  if handle in assets.model_catalog {
    // log.debugf("Model: %v already loaded, reusing", path)
    return handle, true
  }

  assets.model_catalog[handle], ok = make_model(path)

  if !ok {
    log.debugf("Model: %v unable to be loaded", path)
    assets.model_catalog[handle], ok = make_model()
  }

  return handle, ok
}

get_model :: proc(handle: Model_Handle) -> ^Model {
  return &assets.model_catalog[handle] or_else nil
}

load_texture :: proc(name: string, nonlinear_color: bool = false,
                     in_texture_dir: bool = true) -> (handle: Texture_Handle, ok: bool) {
  path := filepath.join({TEXTURE_DIR, name}, context.temp_allocator) if in_texture_dir else name

  handle = cast(Texture_Handle) hash_name(path)

  // Already loaded
  if handle in assets.texture_catalog {
    // log.debugf("Texture: %v already loaded, reusing", path)
    return handle, true
  }

  assets.texture_catalog[handle], ok = make_texture(path, nonlinear_color)

  if !ok {
    log.debugf("Texture: %v unable to be loaded", path)
    assets.texture_catalog[handle] = make_texture_from_missing()
  }

  return handle, ok
}

get_texture :: proc(handle: Texture_Handle) -> ^Texture {
  return &assets.texture_catalog[handle] or_else nil
}
