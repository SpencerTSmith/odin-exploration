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

	// Angle's Cosines
	inner_cutoff:		 f32,
	outer_cutoff:		 f32,
}

add_point_light :: proc(program: Shader_Program, light: Point_Light) {
		set_shader_uniform(program, "point_lights[0].position",  light.position)
		set_shader_uniform(program, "point_lights[0].color",		 light.color)
		set_shader_uniform(program, "point_lights[0].ambient",   light.ambient)
		set_shader_uniform(program, "point_lights[0].diffuse",   light.diffuse)
		set_shader_uniform(program, "point_lights[0].specular",  light.diffuse)
		set_shader_uniform(program, "point_lights[0].constant",  light.constant)
		set_shader_uniform(program, "point_lights[0].linear",		 light.linear)
		set_shader_uniform(program, "point_lights[0].quadratic", light.quadratic)
}
