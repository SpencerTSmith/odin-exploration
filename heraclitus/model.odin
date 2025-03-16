package main

import "core:fmt"
import "core:strings"

import "vendor:cgltf"

MAX_MODEL_MESHES		:: 10
MAX_MODEL_MATERIALS :: 10
Model :: struct {
	materials:			 [MAX_MODEL_MATERIALS]Material,
	materials_count: u32,
	meshes:					 [MAX_MODEL_MESHES]Mesh,
	meshes_count:    u32,
}

make_model_from_file :: proc(file_path: string) -> (model: Model, ok: bool) {
  c_path := strings.unsafe_string_to_cstring(file_path)

  options: cgltf.options
  data, result := cgltf.parse_file(options, c_path)
  if result == .success {
    defer cgltf.free(data)


  } else do fmt.printf("Unable to parse cgltf file \"%v\"\n", file_path)

  return
}
