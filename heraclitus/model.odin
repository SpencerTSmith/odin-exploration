package main

import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:mem"

import "vendor:cgltf"
import gl "vendor:OpenGL"

Vertex_Array_Object :: distinct u32
Vertex_Buffer       :: distinct u32

Mesh_Vertex :: struct {
  position: vec3,
  uv:        vec2,
  normal:    vec3,
}

Mesh_Index :: distinct u32

// TODO(ss): Basically begging to set this up as just 1 multi-draw indirect per model,
// instead of one regular draw per mesh, As well this may be more akin to a GLTF "primitive"
Mesh :: struct {
  index_offset:   i32,
  index_count:    i32,
  material_index: i32,
}

// HACK(ss): Don't know how i feel about just statically storing these
MAX_MODEL_MESHES    :: 200
MAX_MODEL_MATERIALS :: 30
// A model is composed of ONE vertex buffer containing both vertices and indices, vertices first, then indices
// at the right alignment, with "sub" meshes (gltf primitives like) that share the same material
Model :: struct {
  array:          Vertex_Array_Object,
  buffer:         Vertex_Buffer, // Contains both vertices and, at the end, indices
  vertex_count:   i32,
  index_count:    i32,
  index_offset:   i32, // Offset into the single buffer to find indices

  // Sub triangle meshes, also index into a range of the overall buffer
  meshes:         [MAX_MODEL_MESHES]Mesh,
  mesh_count:     int,

  materials:      [MAX_MODEL_MATERIALS]Material,
  material_count: int,
}

Skybox :: struct {
  array:   Vertex_Array_Object,
  buffer:  Vertex_Buffer,
  texture: Texture,
}

make_model :: proc{
  make_model_from_file,
  make_model_from_data,
  make_model_from_default_white_cube,
  make_model_from_data_one_material_one_mesh,
}

// Takes in all vertices and all indices.. then a slice of the materials and a slice of the meshes
make_model_from_data :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index, materials: []Material, meshes: []Mesh, allocator := context.allocator) -> (model: Model, ok: bool) {
  // FIXME: Just save this in the state, instead of querying every time
  min_alignment: i32
  gl.GetIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, &min_alignment)

  vertex_length := len(vertices) * size_of(Mesh_Vertex)
  index_length  := len(indices)  * size_of(Mesh_Index)

  // Lengths after we align to the minimum
  vertex_length_align := mem.align_forward_int(vertex_length, int(min_alignment))
  index_length_align  := mem.align_forward_int(index_length,  int(min_alignment))

  vertex_offset := 0
  index_offset  := vertex_length_align

  buffer: u32
  gl.CreateBuffers(1, &buffer)
  gl.NamedBufferStorage(buffer, vertex_length_align + index_length_align, nil, gl.DYNAMIC_STORAGE_BIT)

  gl.NamedBufferSubData(buffer, vertex_offset, vertex_length, raw_data(vertices))
  gl.NamedBufferSubData(buffer, index_offset,  index_length,  raw_data(indices))

  vao: u32
  gl.CreateVertexArrays(1, &vao)
  // Same buffer for both indices and vertices!
  gl.VertexArrayVertexBuffer(vao, 0, buffer, vertex_offset, size_of(Mesh_Vertex))
  gl.VertexArrayElementBuffer(vao, buffer)

  vertex: Mesh_Vertex
  // position: vec3
  gl.EnableVertexArrayAttrib(vao,  0)
  gl.VertexArrayAttribFormat(vao,  0, len(vertex.position), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.position)))
  gl.VertexArrayAttribBinding(vao, 0, 0)
  // uv: vec2
  gl.EnableVertexArrayAttrib(vao,  1)
  gl.VertexArrayAttribFormat(vao,  1, len(vertex.uv), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.uv)))
  gl.VertexArrayAttribBinding(vao, 1, 0)
  // normal: vec3
  gl.EnableVertexArrayAttrib(vao,  2)
  gl.VertexArrayAttribFormat(vao,  2, len(vertex.normal), gl.FLOAT, gl.FALSE, u32(offset_of(vertex.normal)))
  gl.VertexArrayAttribBinding(vao, 2, 0)

  model = Model{
    array      = Vertex_Array_Object(vao),
    buffer     = Vertex_Buffer(buffer),
    vertex_count = i32(len(vertices)),
    index_count  = i32(len(indices)),
    index_offset = i32(index_offset),
  }

  if len(materials) <= len(model.materials) {
    mem.copy(raw_data(&model.materials), raw_data(materials), len(materials) * size_of(Material))
    model.material_count = len(materials)
  } else {
    fmt.printf("Too many materials for model!")
  }

  if len(meshes) <= len(model.meshes) {
    mem.copy(raw_data(&model.meshes), raw_data(meshes), len(meshes) * size_of(Mesh))
    model.mesh_count = len(meshes)
  } else {
    fmt.printf("Too many meshes for model!")
  }

  // Can these fail?
  ok = true
  return
}

// FIXME: Big assumptions, That this is one model, that the diffuse is the pbr_metallic_roughness.base color
// That the image is always a separate image file (png, jpg, etc.)
make_model_from_file :: proc(file_path: string) -> (model: Model, ok: bool) {
  // Use the temp for filepath string manipulation, and for storing the vertices and indices temprorarily
  defer free_all(context.temp_allocator)

  c_path := strings.clone_to_cstring(file_path, allocator = context.temp_allocator)
  dir := filepath.dir(file_path, allocator = context.temp_allocator)

  options: cgltf.options
  data, result := cgltf.parse_file(options, c_path)
  if result == .success && cgltf.load_buffers(options, data, c_path) == .success {
    defer cgltf.free(data)

    model_materials := make([dynamic]Material, allocator = context.temp_allocator)
    reserve(&model_materials, len(data.materials))

    // Collect materials, only diffuse for now
    for material, idx in data.materials {
      if material.has_pbr_metallic_roughness {
        diffuse_path:   string
        specular_path:  string
        emissive_path:  string

        if material.pbr_metallic_roughness.base_color_texture.texture != nil {
          relative := string(material.pbr_metallic_roughness.base_color_texture.texture.image_.uri)

          slices := []string{dir, relative}
          // HACK: For some reason if all the paths are in the temp allocator when string joins happen,
          // paths get joined to eachother?
          diffuse_path = strings.join(slices, filepath.SEPARATOR_STRING)
        }
        defer delete(diffuse_path)

        if material.emissive_texture.texture != nil {
          relative := string(material.emissive_texture.texture.image_.uri)

          slices := []string{dir, relative}
          emissive_path = strings.join(slices, filepath.SEPARATOR_STRING, allocator = context.temp_allocator)
        }

        // TODO: specular, shininess?

        mesh_material: Material
        mesh_material = make_material(diffuse_path, specular_path, emissive_path) or_return
        append(&model_materials, mesh_material)
      }
    }

    // Each primitive will be its own mesh
    model_meshes := make([dynamic]Mesh, allocator = context.temp_allocator)
    model_mesh_count: uint

    // Just reserve the full amout of vertices and indices that we will need
    model_verts := make([dynamic]Mesh_Vertex, allocator = context.temp_allocator)
    model_verts_count:  uint
    model_index := make([dynamic]Mesh_Index,  allocator = context.temp_allocator)
    model_index_count:  uint

    for mesh, idx in data.meshes {
      for primitive in mesh.primitives {
        for attribute in primitive.attributes {
          if attribute.type == .position {
              model_verts_count += attribute.data.count
          }
        }

        if primitive.indices != nil {
          model_index_count += primitive.indices.count
        }

        model_mesh_count += 1
      }
    }
    reserve(&model_meshes, len(data.meshes))

    reserve(&model_verts, model_verts_count)
    reserve(&model_index, model_index_count)

    // We only load the very first mesh, since this assumes that we are only loading 1 model
    gltf_model := data.meshes[0]
    for primitive in gltf_model.primitives {
      // Get the material
      new_mesh: Mesh
      new_mesh.material_index = i32(cgltf.material_index(data, primitive.material))
      new_mesh.index_offset = i32(len(model_index)) // Off by 1?

      // For now we only collect the position, normal, uv
      position_access: ^cgltf.accessor
      normal_access:   ^cgltf.accessor
      uv_access:       ^cgltf.accessor

      for attribute in primitive.attributes {
        switch(attribute.type) {
        case .position:
          position_access = attribute.data
        case .normal:
          normal_access = attribute.data
        case .texcoord:
          uv_access = attribute.data
        case .invalid:
          fallthrough
        case .tangent:
          fallthrough
        case .color:
          fallthrough
        case .joints:
          fallthrough
        case .weights:
          fallthrough
        case .custom:
        // fmt.println("Don't know how to handle this primitive")
        }
      }

      mesh_vert_count := position_access.count

      if position_access != nil &&
      normal_access != nil &&
      uv_access != nil
      {
        for i in 0..<mesh_vert_count {
          new_vertex: Mesh_Vertex

          ok := cgltf.accessor_read_float(position_access, i, raw_data(&new_vertex.position), 3)
          if !ok {
            fmt.println("Trouble reading vertex position")
          }
          ok = cgltf.accessor_read_float(normal_access, i, raw_data(&new_vertex.normal), 3)
          if !ok {
            fmt.println("Trouble reading vertex normal")
          }
          ok = cgltf.accessor_read_float(uv_access, i, raw_data(&new_vertex.uv), 2)
          if !ok {
            fmt.println("Trouble reading vertex uv")
          }

          append(&model_verts, new_vertex)
        }
      }

      mesh_index_count := primitive.indices.count
      new_mesh.index_count = i32(mesh_index_count)

      if primitive.indices != nil {
        for i in 0..<mesh_index_count {
          new_index := Mesh_Index(cgltf.accessor_read_index(primitive.indices, i))
          append(&model_index, new_index)
        }
      }

      append(&model_meshes, new_mesh)
    }

    assert(len(model_verts) == int(model_verts_count))
    assert(len(model_index) == int(model_index_count))

    model = make_model_from_data(model_verts[:], model_index[:], model_materials[:], model_meshes[:]) or_return
  } else do fmt.printf("Unable to parse cgltf file \"%v\"\n", file_path)
  return
}

make_model_from_default_container :: proc() -> (model: Model, ok: bool) {
  mesh: Mesh = {
    material_index = 0,
    index_offset   = 0,
    index_count    = 36,
  }
  meshes: []Mesh = {mesh}
  material := make_material("./assets/container2.png", "./assets/container2_specular.png", shininess = 64.0) or_return
  materials: []Material = {material}

  model = make_model_from_data(DEFAULT_CUBE_VERT, DEFAULT_CUBE_INDX, materials, meshes) or_return
  return
}

make_model_from_default_white_cube :: proc() -> (model: Model, ok: bool) {
  mesh: Mesh = {
    material_index = 0,
    index_offset   = 0,
    index_count    = 36,
  }
  meshes: []Mesh = {mesh}
  material := make_material() or_return
  materials: []Material = {material}

  model = make_model_from_data(DEFAULT_CUBE_VERT, DEFAULT_CUBE_INDX, materials, meshes) or_return
  return
}

make_model_from_data_one_material_one_mesh :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index,
                                                   material: Material) -> (model: Model, ok: bool) {
  mesh    := Mesh{
    index_count    = i32(len(indices)),
    index_offset   = 0,
    material_index = 0,
  }
  mesh_slice: []Mesh = {mesh}
  material_slice: []Material = {material}
  model, ok = make_model_from_data(vertices, indices, material_slice, mesh_slice)
  return
}

draw_model :: proc(using model: Model) {
  assert(state.current_shader.id != 0)

  gl.BindVertexArray(u32(array))
  defer gl.BindVertexArray(0)

  for i in 0..<mesh_count {
    if "material.diffuse" in state.current_shader.uniforms {
      bind_material(materials[meshes[i].material_index])
    }
    true_offset := model.index_offset + meshes[i].index_offset
    gl.DrawElements(gl.TRIANGLES, meshes[i].index_count, gl.UNSIGNED_INT, rawptr(uintptr(true_offset)))
  }
}

free_model :: proc(using model: ^Model) {
  for &material in materials {
    free_material(&material)
  }
  gl.DeleteBuffers(1, cast(^u32)&buffer)
  gl.DeleteVertexArrays(1, cast(^u32)&array)
}

make_skybox :: proc(file_paths: [6]string) -> (skybox: Skybox, ok: bool) {
  skybox_verts := SKYBOX_VERTICES
  buffer: u32
  gl.CreateBuffers(1, &buffer)
  gl.NamedBufferStorage(buffer, len(skybox_verts) * size_of(f32), raw_data(skybox_verts), 0)

  vao: u32
  gl.CreateVertexArrays(1, &vao)
  gl.VertexArrayVertexBuffer(vao, 0, buffer, 0, 3 * size_of(f32))

  // Position only needed
  gl.EnableVertexArrayAttrib(vao,  0)
  gl.VertexArrayAttribFormat(vao,  0, 3, gl.FLOAT, gl.FALSE, 0)
  gl.VertexArrayAttribBinding(vao, 0, 0)

  texture := make_texture_cube_map(file_paths) or_return

  skybox = {
    array   = Vertex_Array_Object(vao),
    buffer  = Vertex_Buffer(buffer),
    texture = texture,
  }
  ok = true
  return skybox, ok
}

// Remember... binds the skybox shader
draw_skybox :: proc(skybox: Skybox) {
  bind_shader_program(state.skybox_program)
  gl.DepthFunc(gl.LEQUAL)
  gl.BindVertexArray(u32(skybox.array))
  bind_texture(skybox.texture, 0)
  set_shader_uniform(state.skybox_program, "skybox", 0)
  gl.DrawArrays(gl.TRIANGLES, 0, 36)
  gl.DepthFunc(gl.LESS)
}

free_skybox :: proc(using skybox: ^Skybox) {
  free_texture(&texture)
  gl.DeleteBuffers(1, cast(^u32)&buffer)
  gl.DeleteVertexArrays(1, cast(^u32)&array)
}

SKYBOX_VERTICES :: []f32{
  -1.0,  1.0, -1.0,
  -1.0, -1.0, -1.0,
   1.0, -1.0, -1.0,
   1.0, -1.0, -1.0,
   1.0,  1.0, -1.0,
  -1.0,  1.0, -1.0,
  -1.0, -1.0,  1.0,
  -1.0, -1.0, -1.0,
  -1.0,  1.0, -1.0,
  -1.0,  1.0, -1.0,
  -1.0,  1.0,  1.0,
  -1.0, -1.0,  1.0,
   1.0, -1.0, -1.0,
   1.0, -1.0,  1.0,
   1.0,  1.0,  1.0,
   1.0,  1.0,  1.0,
   1.0,  1.0, -1.0,
   1.0, -1.0, -1.0,
  -1.0, -1.0,  1.0,
  -1.0,  1.0,  1.0,
   1.0,  1.0,  1.0,
   1.0,  1.0,  1.0,
   1.0, -1.0,  1.0,
  -1.0, -1.0,  1.0,
  -1.0,  1.0, -1.0,
   1.0,  1.0, -1.0,
   1.0,  1.0,  1.0,
   1.0,  1.0,  1.0,
  -1.0,  1.0,  1.0,
  -1.0,  1.0, -1.0,
  -1.0, -1.0, -1.0,
  -1.0, -1.0,  1.0,
   1.0, -1.0, -1.0,
   1.0, -1.0, -1.0,
  -1.0, -1.0,  1.0,
   1.0, -1.0,  1.0
}

DEFAULT_TRIANGLE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, 0.0}}, // bottom right
  { position = { 0.5, -0.5, 0.0}}, // bottom left
  { position = { 0.0,  0.5, 0.0}}, // top
};

DEFAULT_SQUARE_VERT :: []Mesh_Vertex {
  { position = { 0.5,  0.5, 0.0}, uv = {1.0, 0.0}, normal = {0.0,  0.0, 1.0} }, // top right
  { position = { 0.5, -0.5, 0.0}, uv = {1.0, 1.0}, normal = {0.0,  0.0, 1.0} }, // bottom right
  { position = {-0.5, -0.5, 0.0}, uv = {0.0, 1.0}, normal = {0.0,  0.0, 1.0} }, // bottom left
  { position = {-0.5,  0.5, 0.0}, uv = {0.0, 0.0}, normal = {0.0,  0.0, 1.0} }, // top left
}

DEFAULT_SQUARE_INDX :: []Mesh_Index {
  3, 1, 0,   // first triangle
  3, 2, 1,   // second triangle
}

DEFAULT_CUBE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0, -1.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0, -1.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {1.0, 0.0}, normal = { 0.0,  0.0, -1.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0, -1.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0, -1.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0,  0.0, -1.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0,  1.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0,  0.0,  1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0,  1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0,  1.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {0.0, 1.0}, normal = { 0.0,  0.0,  1.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0,  1.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {-1.0,  0.0,  0.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {-1.0,  0.0,  0.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {-1.0,  0.0,  0.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {-1.0,  0.0,  0.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {-1.0,  0.0,  0.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {-1.0,  0.0,  0.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 1.0,  0.0,  0.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 1.0,  0.0,  0.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 1.0,  0.0,  0.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 1.0,  0.0,  0.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 1.0,  0.0,  0.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 1.0,  0.0,  0.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0, -1.0,  0.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0, -1.0,  0.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0, -1.0,  0.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0, -1.0,  0.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0, -1.0,  0.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0, -1.0,  0.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0,  1.0,  0.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0,  1.0,  0.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0,  1.0,  0.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0,  1.0,  0.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0,  1.0,  0.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0,  1.0,  0.0} },
}

DEFAULT_CUBE_INDX :: []Mesh_Index {
   0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17,
  18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35
}

DEFAULT_MODEL_POSITIONS :: []vec3 {
    { 0.0,  0.0,   0.0},
    { 2.0,  5.0, -15.0},
    {-1.5, -2.2,  -2.5},
    {-3.8, -2.0, -12.3},
    { 2.4, -0.4,  -3.5},
    {-1.7,  3.0,  -7.5},
    { 1.3, -2.0,  -2.5},
    { 1.5,  2.0,  -2.5},
    { 1.5,  0.2,  -1.5},
    {-1.3,  1.0,  -1.5},
}
