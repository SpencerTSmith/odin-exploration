package main

Point_Light :: struct {
	position: vec3,

	ambient:	vec3,
	diffuse:	vec3,
	specular: vec3,
}

Global_Light :: struct {
	direction: vec3,

	ambient:	vec3,
	diffuse:	vec3,
	specular: vec3,
}
