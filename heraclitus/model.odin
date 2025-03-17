package main

import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:mem"

import "vendor:cgltf"
import gl "vendor:OpenGL"

Vertex_Array_Object :: distinct u32
Vertex_Buffer :: distinct u32
Index_Buffer  :: distinct u32

Mesh_Vertex :: struct {
  position: vec3,
  uv:        vec2,
  normal:    vec3,
}

Mesh_Index :: distinct u32

Mesh :: struct {
  index_offset:   i32,
  index_count:    i32,
  material_index: i32,
}

// A model is composed of ONE vertex buffer containing both vertices and indices
// And "sub" meshes that share the same material
MAX_MODEL_MESHES    :: 100
MAX_MODEL_MATERIALS :: 10
Model :: struct {
  array:      Vertex_Array_Object,
  buffer:       Vertex_Buffer, // Contains both vertices and indices
  vert_count:  i32,
  idx_count:   i32,
  idx_offset: i32,

  // Sub triangle meshes, index into the overall buffer
  meshes:         [MAX_MODEL_MESHES]Mesh,
  mesh_count:     int,
  materials:      [MAX_MODEL_MATERIALS]Material,
  material_count: int,
}

make_model :: proc{
  make_model_from_file,
  make_model_from_data,
}

// Takes in all vertices and all indices.. then a slice of the materials and a slice of the meshes
make_model_from_data :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index, materials: []Material, meshes: []Mesh) -> (model: Model, ok: bool) {
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
    vert_count = i32(len(vertices)),
    idx_count  = i32(len(vertices)),
    idx_offset = i32(index_offset),
  }

  if len(materials) <= len(model.materials) {
    mem.copy_non_overlapping(raw_data(&model.materials), raw_data(materials),  len(materials) * size_of(materials))
    model.material_count = len(materials)
  } else {
    fmt.printf("Too many materials for model!")
  }
  
  if len(meshes) <= len(model.meshes) {
    mem.copy_non_overlapping(raw_data(&model.meshes), raw_data(meshes),  len(meshes) * size_of(meshes))
    model.mesh_count = len(meshes)
  } else {
    fmt.printf("Too many meshes for model!")
  }

  return
}

// FIXME(ss): Big assumptions, That this is one model, that the diffuse is the pbr_metallic_roughness base color
// That the image is always a separate png or such
// Just extracts all meshes and materials into a single model
make_model_from_file :: proc(file_path: string) -> (model: Model, ok: bool) {
  c_path := strings.unsafe_string_to_cstring(file_path)

  options: cgltf.options
  data, result := cgltf.parse_file(options, c_path)
  if result == .success && cgltf.load_buffers(options, data, c_path) == .success {
    defer cgltf.free(data)

    dir := filepath.dir(file_path, allocator = context.temp_allocator)

    fmt.printf("Model \"%v\" has %v meshes and %v materials\n", file_path, len(data.meshes), len(data.materials))

    model_materials: [dynamic]Material
    reserve(&model_materials, len(data.materials))

    model_meshes: [dynamic]Mesh
    reserve(&model_meshes, len(data.meshes))

    // Collect materials, only diffuse for now
    for material, idx in data.materials {
      relative := string(material.pbr_metallic_roughness.base_color_texture.texture.image_.uri)

      slice := []string{dir, relative}
      full_path := strings.join(slice, filepath.SEPARATOR_STRING, allocator=context.temp_allocator)


      material: Material
      diffuse, _ := make_texture(full_path)
      material.diffuse = diffuse

      append(&model_materials, material)
    }

    // Just reserve the full amout of vertices and indices that we will need
    model_verts: [dynamic]Mesh_Vertex
    model_index: [dynamic]Mesh_Index
    model_verts_count:  uint
    model_index_count: uint
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
      }
    }
    reserve(&model_verts, model_verts_count)
    fmt.printf("Model in total has %v vertices\n", model_verts_count)
    reserve(&model_index, model_index_count)
    fmt.printf("Model in total has %v indices\n", model_index_count)

    for mesh, idx in data.meshes {
      // Get the material
      new_mesh: Mesh
      new_mesh.material_index = i32(cgltf.material_index(data, mesh.primitives[0].material))

      // For now we only collect the position, normal, uv
      for primitive in mesh.primitives {
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
        fmt.printf("Mesh %v has %v vertices\n", idx, mesh_vert_count)
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
        fmt.printf("Mesh %v has %v indices\n", idx, mesh_vert_count)
        if primitive.indices != nil {
          for i in 0..<mesh_index_count {
            new_index := Mesh_Index(cgltf.accessor_read_index(primitive.indices, i))
            append(&model_index, new_index)
          }
        }
        // fmt.printf("%#v\n", temp_verts)
        // fmt.printf("%#v\n", temp_index)
      }

      append(&model_meshes, new_mesh)
    }

    assert(len(model_verts) == int(model_verts_count))
    assert(len(model_index) == int(model_index_count))


  } else do fmt.printf("Unable to parse cgltf file \"%v\"\n", file_path)

  free_all(context.temp_allocator)
  return
}

draw_model :: proc(using model: Model, program: Shader_Program) {
  assert(state.current_shader.id == program.id)

  gl.BindVertexArray(u32(array))
  defer gl.BindVertexArray(0)

  for i in 0..<mesh_count {
    bind_material(materials[meshes[i].material_index], program)
    true_offset := model.idx_offset + meshes[i].index_offset
    gl.DrawElements(gl.TRIANGLES, meshes[i].index_count, gl.UNSIGNED_INT, rawptr(uintptr(true_offset)))
  }
}

free_model :: proc(using model: ^Model) {
  gl.DeleteBuffers(1, cast(^u32)&buffer)
  gl.DeleteVertexArrays(1, cast(^u32)&array)
}

DEFAULT_TRIANGLE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, 0.0}}, // bottom right
  { position = { 0.5, -0.5, 0.0}}, // bottom left
  { position = { 0.0,  0.5, 0.0}}, // top
};

DEFAULT_SQUARE_VERT :: []Mesh_Vertex {
  { position = { 0.5,  0.5, 0.0}, uv = {1.0, 1.0}}, // top right
  { position = { 0.5, -0.5, 0.0}, uv = {1.0, 0.0}}, // bottom right
  { position = {-0.5, -0.5, 0.0}, uv = {0.0, 0.0}}, // bottom left
  { position = {-0.5,  0.5, 0.0}, uv = {0.0, 1.0}}, // top left
}

DEFAULT_SQUARE_IDX :: []Mesh_Index {
  0, 1, 3,   // first triangle
  1, 2, 3,   // second triangle
}

DEFAULT_CUBE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 0.0}, normal = {0.0,  0.0, -1.0}},
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {0.0,  0.0, -1.0}},
  { position = { 0.5, -0.5, -0.5}, uv = {1.0, 0.0}, normal = {0.0,  0.0, -1.0}},
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {0.0,  0.0, -1.0}},
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 0.0}, normal = {0.0,  0.0, -1.0}},
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = {0.0,  0.0, -1.0}},
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {0.0,  0.0,  1.0}},
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = {0.0,  0.0,  1.0}},
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 1.0}, normal = {0.0,  0.0,  1.0}},
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 1.0}, normal = {0.0,  0.0,  1.0}},
  { position = {-0.5,  0.5,  0.5}, uv = {0.0, 1.0}, normal = {0.0,  0.0,  1.0}},
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {0.0,  0.0,  1.0}},
  { position = {-0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {0.0, -1.0,  0.0}},
  { position = { 0.5, -0.5, -0.5}, uv = {1.0, 1.0}, normal = {0.0, -1.0,  0.0}},
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = {0.0, -1.0,  0.0}},
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = {0.0, -1.0,  0.0}},
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {0.0, -1.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {0.0, -1.0,  0.0}},
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = {0.0,  1.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {0.0,  1.0,  0.0}},
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {0.0,  1.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {0.0,  1.0,  0.0}},
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = {0.0,  1.0,  0.0}},
  { position = {-0.5,  0.5,  0.5}, uv = {0.0, 0.0}, normal = {0.0,  1.0,  0.0}},
}

DEFAULT_CUBE_INDX :: []Mesh_Index {
   0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17,
  18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35
}
