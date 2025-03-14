package main

Point_Light :: struct {
	position: vec3,

	color:		vec3,
	ambient:	vec3,
	diffuse:	vec3,
	specular: vec3,

	// Attenuation
	constant:  f32,
	linear:		 f32,
	quadratic: f32,
}

Direction_Light :: struct {
	direction: vec3,

	color:		vec3,
	ambient:	 vec3,
	diffuse:	 vec3,
	specular:  vec3,
}

Spot_Light :: struct {
	position:  vec3,
	direction: vec3,

	color:		vec3,
	ambient:	 vec3,
	diffuse:	 vec3,
	specular:  vec3,

	// Attenuation
	constant:  f32,
	linear:		 f32,
	quadratic: f32,

	// Angle's Cosine
	cutoff:		 f32,
}
