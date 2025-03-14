#version 450 core

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 world_position;

layout(location = 0) out vec4 frag_color;

// Reflections
struct Material {
	sampler2D diffuse;
	sampler2D	specular;
	sampler2D emission;
	float			shininess;
};
uniform Material material;

struct Point_Light {
	vec3 position;

	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	// Attenuation
	float constant;
	float linear;
	float quadratic;
};
uniform Point_Light point_light;

struct Global_Light {
	vec3 direction;

	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};
uniform Global_Light global_light;

uniform vec3 camera_position;

vec3 calc_point_phong(Point_Light light, Material material, vec3 norm, vec3 view_direction, vec3 frag_position) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, in_uv));

	// DIFFUSE
	vec3 light_direction = normalize(light.position - world_position);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(norm, light_direction), 0.0);
	vec3 diffuse = light.diffuse * diffuse_intensity * vec3(texture(material.diffuse, in_uv));

	// SPECULAR
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, norm);
	// Is the reflection pointing towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = light.specular * (specular_intensity * vec3(texture(material.specular, in_uv)));

	// ATTENUATION
	float distance = length(light.position - frag_position);
	float attenuation = 1.0 / (light.constant + light.linear * distance + light.quadratic * (distance * distance));

	vec3 phong = attenuation * (ambient + diffuse + specular);

	return phong;
}

vec3 calc_global_phong(Global_Light light, Material material, vec3 norm, vec3 view_direction) {
	// AMBIENT:
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, in_uv));

	// DIFFUSE:
	vec3 light_direction = normalize(-light.direction);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(norm, light_direction), 0.0);
	vec3 diffuse = light.diffuse * diffuse_intensity * vec3(texture(material.diffuse, in_uv));

	// SPECULAR:
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, norm);
	// Is the reflection globaling towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = light.specular * (specular_intensity * vec3(texture(material.specular, in_uv)));

	vec3 phong = ambient + diffuse + specular;

	return phong;
}

void main() {
	vec3 norm = normalize(in_normal);
	vec3 view_direction = normalize(camera_position - world_position);

	vec3 point_phong = calc_point_phong(point_light, material, norm, view_direction, world_position);

	vec3 global_phong = calc_global_phong(global_light, material, norm, view_direction);

	// EMISSION
	vec3 emission = vec3(texture(material.emission, in_uv));

	vec3 result = point_phong + global_phong + emission;

  frag_color = vec4(result, 1.0);
}
