package main

import "core:math/linalg/glsl"

Entity :: struct {
	position:	vec3,
	scale:		vec3,
	rotation: vec3,

	mesh:			^Mesh,
}

// yxz euler angle
get_entity_model_mat4 :: proc(entity: Entity) -> (model: mat4) {
	translation := glsl.mat4Translate(entity.position)
	rotation_y := glsl.mat4Rotate({0.0, 1.0, 0.0}, glsl.radians_f32(entity.rotation.y))
	rotation_x := glsl.mat4Rotate({1.0, 0.0, 0.0}, glsl.radians_f32(entity.rotation.x))
	rotation_z := glsl.mat4Rotate({0.0, 0.0, 1.0}, glsl.radians_f32(entity.rotation.z))
	scale := glsl.mat4Scale(entity.scale)

	model = translation * rotation_y * rotation_x * rotation_z * scale
	return
}
