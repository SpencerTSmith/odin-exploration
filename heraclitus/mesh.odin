package main

import "core:fmt"

import gl "vendor:OpenGL"

Array_Object :: distinct u32
Vertex_Buffer :: distinct u32
Index_Buffer :: distinct u32

Mesh_Vertex :: struct {
	position: vec3,
	uv:				vec2,
	normal:		vec3,
}

Mesh_Index :: distinct u32

Mesh :: struct {
	array:	Array_Object,

	vertices:	 	Vertex_Buffer,
	vert_count:	i32,

	indices:	 	Index_Buffer,
	idx_count: 	i32,
}

make_mesh :: proc {
	make_mesh_from_data,
	make_mesh_from_file,
}

// Pass nil for indices if not using an index buffer
make_mesh_from_data :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index = nil) -> (mesh: Mesh) {
  vbo: u32
  gl.CreateBuffers(1, &vbo)
  gl.NamedBufferStorage(vbo, len(vertices) * size_of(Mesh_Vertex), raw_data(vertices), 0)

  ebo: u32
  if indices != nil {
    gl.CreateBuffers(1, &ebo)
    gl.NamedBufferStorage(ebo, len(indices) * size_of(Mesh_Index), raw_data(indices), 0)
  }

  vao: u32
  gl.CreateVertexArrays(1, &vao)
  gl.VertexArrayVertexBuffer(vao, 0, vbo, 0, size_of(Mesh_Vertex))
  if indices != nil {
   gl.VertexArrayElementBuffer(vao, ebo)
  }

  {
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
  }

	mesh = {
		array = Array_Object(vao),
		vertices = Vertex_Buffer(vbo),
		vert_count = i32(len(vertices)),
		indices = Index_Buffer(ebo),
		idx_count = i32(len(indices)),
	}
	return
}

make_mesh_from_file :: proc(file_path: string) -> (mesh: Mesh) {
	return
}

free_mesh :: proc(mesh: ^Mesh) {
	using mesh
	gl.DeleteVertexArrays(1, cast(^u32)&array)
	gl.DeleteBuffers(1, cast(^u32)&vertices)

	if indices != 0 {
		gl.DeleteBuffers(1, cast(^u32)&indices)
	}
}

draw_mesh :: proc(mesh: Mesh) {
	gl.BindVertexArray(u32(mesh.array))
	defer gl.BindVertexArray(0)

	if mesh.indices != 0 {
		gl.DrawElements(gl.TRIANGLES, mesh.idx_count, gl.UNSIGNED_INT, nil)
	} else {
		gl.DrawArrays(gl.TRIANGLES, 0, mesh.vert_count)
	}
}

bind_mesh :: proc(mesh: Mesh) {
	gl.BindVertexArray(u32(mesh.array))
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

