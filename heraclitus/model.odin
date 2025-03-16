package main

MAX_MODEL_MESHES		:: 10
MAX_MODEL_MATERIALS :: 10
Model :: struct {
	materials:			 [MAX_MODEL_MATERIALS]Material,
	materials_count: u32,
	meshes:					 [MAX_MODEL_MESHES]Mesh,
	meshes_count:    u32,
}
