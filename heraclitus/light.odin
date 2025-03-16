package main

// Attenuation = {x = constant, y = linear, z = quadratic}

PAD :: [4]byte

LIGHT_UBO_BINDING :: 1
MAX_POINT_LIGHTS :: 16
Light_UBO :: struct #min_field_align(16) {
	direction:		Direction_Light,
	points:		 		[MAX_POINT_LIGHTS]Point_Light,
	points_count: u32,
	spot:					Spot_Light,
}

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
