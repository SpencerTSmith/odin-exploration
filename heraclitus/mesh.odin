package main

import gl "vendor:OpenGL"

Array_Buffer :: distinct u32
Vertex_Buffer :: distinct u32
Index_Buffer :: distinct u32

Mesh_Vertex :: struct {
	position: vec3,
	color:		vec3,
	uv:				vec2,
	normal:		vec3,
}

Mesh_Index :: distinct u32

Mesh :: struct {
	array:	Array_Buffer,

	vertices:	 	Vertex_Buffer,
	vert_count:	i32,

	indices:	 	Index_Buffer,
	idx_count: 	i32,
}

DEFAULT_TRIANGLE_VERT :: []Mesh_Vertex {
	{ position = {-0.5, -0.5, 0.0}, color = LEARN_OPENGL_ORANGE}, // bottom right
	{ position = { 0.5, -0.5, 0.0}, color = LEARN_OPENGL_ORANGE}, // bottom left
	{ position = { 0.0,  0.5, 0.0}, color = LEARN_OPENGL_ORANGE}, // top
};

DEFAULT_SQUARE_VERT :: []Mesh_Vertex {
	{ position = { 0.5,  0.5, 0.0}, color = {1.0, 0.0, 0.0}, uv = {1.0, 1.0}}, // top right
  { position = { 0.5, -0.5, 0.0}, color = {0.0, 1.0, 0.0}, uv = {1.0, 0.0}}, // bottom right
  { position = {-0.5, -0.5, 0.0}, color = {0.0, 0.0, 1.0}, uv = {0.0, 0.0}}, // bottom left
  { position = {-0.5,  0.5, 0.0}, color = {1.0, 1.0, 0.0}, uv = {0.0, 1.0}}, // top left
}

DEFAULT_SQUARE_IDX :: []Mesh_Index {
  0, 1, 3,   // first triangle
  1, 2, 3,   // second triangle
}

_DEFAULT_CUBE_VERT :: []Mesh_Vertex {
  { position = { 1.0, -1.0,  1.0,}, color = {1.0, 0.5, 0.5}, uv = {1.0, 0.0}},
  { position = { 1.0,	 1.0,  1.0,}, color = {0.1, 0.1, 0.8}, uv = {1.0, 1.0}},
  { position = { 1.0, -1.0, -1.0,}, color = {0.1, 0.8, 0.2}, uv = {0.0, 0.0}},
  { position = { 1.0,  1.0, -1.0,}, color = {1.0, 1.0, 0.2}, uv = {1.0, 0.0}},
  { position = {-1.0, -1.0,  1.0,}, color = {0.0, 1.0, 1.0}, uv = {1.0, 1.0}},
  { position = {-1.0,  1.0,  1.0,}, color = {1.0, 0.5, 0.2}, uv = {0.0, 0.0}},
  { position = {-1.0, -1.0, -1.0,}, color = {1.0, 0.5, 1.0}, uv = {1.0, 1.0}},
  { position = {-1.0,  1.0, -1.0,}, color = {1.0, 0.0, 0.2}, uv = {0.0, 1.0}},
}

DEFAULT_CUBE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, -0.5}, color = {1.0, 0.5, 0.5}, uv = {0.0, 0.0}, normal = {0.0,  0.0, -1.0}},
  { position = { 0.5, -0.5, -0.5}, color = {0.1, 0.1, 0.8}, uv = {1.0, 0.0}, normal = {0.0,  0.0, -1.0}},
  { position = { 0.5,  0.5, -0.5}, color = {0.1, 0.8, 0.2}, uv = {1.0, 1.0}, normal = {0.0,  0.0, -1.0}},
  { position = { 0.5,  0.5, -0.5}, color = {1.0, 1.0, 0.2}, uv = {1.0, 1.0}, normal = {0.0,  0.0, -1.0}},
  { position = {-0.5,  0.5, -0.5}, color = {0.0, 1.0, 1.0}, uv = {0.0, 1.0}, normal = {0.0,  0.0, -1.0}},
  { position = {-0.5, -0.5, -0.5}, color = {1.0, 0.5, 0.2}, uv = {0.0, 0.0}, normal = {0.0,  0.0, -1.0}},
  { position = {-0.5, -0.5,  0.5}, color = {1.0, 0.5, 1.0}, uv = {0.0, 0.0}, normal = {0.0,  0.0,  1.0}},
  { position = { 0.5, -0.5,  0.5}, color = {1.0, 0.0, 0.2}, uv = {1.0, 0.0}, normal = {0.0,  0.0,  1.0}},
  { position = { 0.5,  0.5,  0.5}, color = {1.0, 0.5, 0.5}, uv = {1.0, 1.0}, normal = {0.0,  0.0,  1.0}},
  { position = { 0.5,  0.5,  0.5}, color = {0.1, 0.1, 0.8}, uv = {1.0, 1.0}, normal = {0.0,  0.0,  1.0}},
  { position = {-0.5,  0.5,  0.5}, color = {0.1, 0.8, 0.2}, uv = {0.0, 1.0}, normal = {0.0,  0.0,  1.0}},
  { position = {-0.5, -0.5,  0.5}, color = {1.0, 1.0, 0.2}, uv = {0.0, 0.0}, normal = {0.0,  0.0,  1.0}},
  { position = {-0.5,  0.5,  0.5}, color = {0.0, 1.0, 1.0}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5,  0.5, -0.5}, color = {1.0, 0.5, 0.2}, uv = {1.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, color = {1.0, 0.5, 1.0}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, color = {1.0, 0.0, 0.2}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5,  0.5}, color = {1.0, 0.5, 0.5}, uv = {0.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5,  0.5,  0.5}, color = {0.1, 0.1, 0.8}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, color = {0.1, 0.8, 0.2}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5,  0.5, -0.5}, color = {1.0, 1.0, 0.2}, uv = {1.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5, -0.5, -0.5}, color = {0.0, 1.0, 1.0}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5, -0.5, -0.5}, color = {1.0, 0.5, 0.2}, uv = {0.0, 1.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5, -0.5,  0.5}, color = {1.0, 0.5, 1.0}, uv = {0.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, color = {1.0, 0.0, 0.2}, uv = {1.0, 0.0}, normal = {1.0,  0.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, color = {1.0, 0.5, 0.5}, uv = {0.0, 1.0}, normal = {0.0, -1.0,  0.0}},
  { position = { 0.5, -0.5, -0.5}, color = {0.1, 0.1, 0.8}, uv = {1.0, 1.0}, normal = {0.0, -1.0,  0.0}},
  { position = { 0.5, -0.5,  0.5}, color = {0.1, 0.8, 0.2}, uv = {1.0, 0.0}, normal = {0.0, -1.0,  0.0}},
  { position = { 0.5, -0.5,  0.5}, color = {1.0, 1.0, 0.2}, uv = {1.0, 0.0}, normal = {0.0, -1.0,  0.0}},
  { position = {-0.5, -0.5,  0.5}, color = {0.0, 1.0, 1.0}, uv = {0.0, 0.0}, normal = {0.0, -1.0,  0.0}},
  { position = {-0.5, -0.5, -0.5}, color = {1.0, 0.5, 0.2}, uv = {0.0, 1.0}, normal = {0.0, -1.0,  0.0}},
  { position = {-0.5,  0.5, -0.5}, color = {1.0, 0.5, 1.0}, uv = {0.0, 1.0}, normal = {0.0,  1.0,  0.0}},
  { position = { 0.5,  0.5, -0.5}, color = {1.0, 0.0, 0.2}, uv = {1.0, 1.0}, normal = {0.0,  1.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, color = {0.1, 0.8, 0.2}, uv = {1.0, 0.0}, normal = {0.0,  1.0,  0.0}},
  { position = { 0.5,  0.5,  0.5}, color = {1.0, 1.0, 0.2}, uv = {1.0, 0.0}, normal = {0.0,  1.0,  0.0}},
  { position = {-0.5,  0.5,  0.5}, color = {0.0, 1.0, 1.0}, uv = {0.0, 0.0}, normal = {0.0,  1.0,  0.0}},
  { position = {-0.5,  0.5, -0.5}, color = {1.0, 0.5, 0.2}, uv = {0.0, 1.0}, normal = {0.0,  1.0,  0.0}},
}

_DEFAULT_CUBE_IDX :: []Mesh_Index {
  4, 2, 0, 2, 7, 3, 6, 5, 7, 1, 7, 5, 0, 3, 1, 4, 1, 5,
  4, 6, 2, 2, 6, 7, 6, 4, 5, 1, 3, 7, 0, 2, 3, 4, 0, 1,
}


// Pass nil for indices if not using an index buffer
make_mesh_from_data :: proc(verts: []Mesh_Vertex, indices: []Mesh_Index) -> (mesh: Mesh) {
	vao: u32
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	vbo: u32
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(verts) * size_of(verts[0]), raw_data(verts), gl.STATIC_DRAW)
	
	ebo: u32
	if indices != nil {
		gl.GenBuffers(1, &ebo)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
		gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(indices[0]), raw_data(indices), gl.STATIC_DRAW);
	}
	
	// Not defering here since it needs to be in this order
	defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
	defer gl.BindVertexArray(0)

	// position: vec3
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Mesh_Vertex), offset_of(Mesh_Vertex, position))
	gl.EnableVertexAttribArray(0)
	// color: vec3
	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Mesh_Vertex), offset_of(Mesh_Vertex, color))
	gl.EnableVertexAttribArray(1)
	// uv: vec2
	gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, size_of(Mesh_Vertex), offset_of(Mesh_Vertex, uv))
	gl.EnableVertexAttribArray(2)
	// normal: vec3
	gl.VertexAttribPointer(3, 3, gl.FLOAT, gl.FALSE, size_of(Mesh_Vertex), offset_of(Mesh_Vertex, normal))
	gl.EnableVertexAttribArray(3)

	mesh = {
		array = Array_Buffer(vao),
		vertices = Vertex_Buffer(vbo),
		vert_count = i32(len(verts)),
		indices = Index_Buffer(ebo),
		idx_count = i32(len(indices)),
	}
	return
}

// make_mesh_from_file :: proc(file_path: string) -> mesh: Mesh {
//
// 	return Mesh{}
// }

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
