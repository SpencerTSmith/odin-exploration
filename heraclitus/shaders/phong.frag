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

struct Light {
	vec3 position;

	vec3 ambient;
	vec3 diffuse;
	// Helpful to think of how "pointed" this light is
	// A flashlight is going to have more specularity than
	// a lamp
	vec3 specular;
};
uniform Light light;

uniform vec3 camera_position;

void main() {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, in_uv));

	// DIFFUSE
	vec3 norm = normalize(in_normal);
	vec3 light_direction = normalize(light.position - world_position);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(norm, light_direction), 0.0);
	vec3 diffuse = light.diffuse * diffuse_intensity * vec3(texture(material.diffuse, in_uv));

	// SPECULAR
	vec3 view_direction = normalize(camera_position - world_position);
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, norm);
	// Is the reflection pointing towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = light.specular * (specular_intensity * vec3(texture(material.specular, in_uv)));

	// EMISSION
	vec3 emission = vec3(texture(material.emission, in_uv));

	vec3 result = ambient + diffuse + specular + emission;

  frag_color = vec4(result, 1.0);
}
