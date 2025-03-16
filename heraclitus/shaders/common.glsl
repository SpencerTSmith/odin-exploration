#version 460 core

struct Material {
	sampler2D diffuse;
	sampler2D	specular;
	sampler2D emission;
	float			shininess;
};

struct Point_Light {
	vec3 position;

	vec3 color;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	// Attenuation
	float constant;
	float linear;
	float quadratic;
};

struct Direction_Light {
	vec3 direction;

	vec3 color;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};

struct Spot_Light {
	vec3 position;
	vec3 direction;

	vec3 color;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	// Attenuation
	float constant;
	float linear;
	float quadratic;

	// Angle's Cosine
	float outer_cutoff;
	float inner_cutoff;
};

#define MAX_POINT_LIGHTS 16
layout(std140, binding = 0) uniform Frame_UBO {
	mat4 projection;
	mat4 view;
	vec3 camera_position;

	Direction_Light direction;
	Point_Light			points[MAX_POINT_LIGHTS];
	uint            points_count;
	Spot_Light      spot;
};
