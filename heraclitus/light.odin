package main

// Attenuation = {x = constant, y = linear, z = quadratic}

PAD :: [4]byte

Point_Light :: struct #align(16){
  position:		 vec3,
  _:PAD,

	color:			 vec3,
  _:PAD,
	attenuation: vec3,

	intensity:	 f32,
  ambient:     f32,
}

Direction_Light :: struct {
  direction:	 vec3,
  _:PAD,

	color:			 vec3,

	intensity:	 f32,
  ambient:     f32,
}

Spot_Light :: struct {
	position:    vec3,
  _:PAD,
	direction:   vec3,
  _:PAD,

	color:			 vec3,
  _:PAD,
	attenuation: vec3,

	intensity:	 f32,
  ambient:     f32,

	// Cosines
	inner_cutoff:	f32,
	outer_cutoff:	f32,
}
