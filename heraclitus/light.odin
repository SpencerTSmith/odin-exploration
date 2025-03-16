package main

// Attenuations = {x = constant, y = linear, z = quadratic}

Point_Light :: struct #min_field_align(16) {
	position:		 vec3,

	color:			 vec3,
	ambient:		 vec3,
	diffuse:		 vec3,
	specular: 	 vec3,

	attenuation: vec3,
}

Direction_Light :: struct #min_field_align(16) {
	direction: vec3,

	color:		 vec3,
	ambient:	 vec3,
	diffuse:	 vec3,
	specular:  vec3,
}

Spot_Light :: struct {
	// Cosines
	inner_cutoff:	f32,
	outer_cutoff:	f32,

	using _: struct #min_field_align(16) {
	position:    vec3,
	direction:   vec3,

	color:		   vec3,
	ambient:	   vec3,
	diffuse:	   vec3,
	specular:    vec3,

	attenuation: vec3,
	},
}
